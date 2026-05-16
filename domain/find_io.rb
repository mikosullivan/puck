#!/usr/bin/env ruby
# domain/find_io.rb
#
# Search for available 3-letter .io domain names.
#
# Walks all 26^3 = 17,576 lowercase three-letter combinations, queries the
# .io WHOIS server (whois.nic.io:43) over a raw TCP socket, and records the
# names that come back as unregistered.
#
# Pure Ruby stdlib — no gems, no `whois` binary required.
#
# Output files (in the same directory as this script):
#   io.txt          one available .io domain per line, appended as found
#   io_checked.txt  one already-checked name per line, used to resume after
#                   an interrupt (start/stop with Ctrl+C is safe)
#
# Rate limiting:
#   - 2 seconds between queries (1,800/hr, comfortable under WHOIS server
#     limits in practice)
#   - On network error, timeout, or rate-limit-looking response: exponential
#     backoff up to 60 s, up to 3 retries, then skip the name for this run
#     (it'll be retried on the next invocation)
#
# Runtime: ~10 hours for a full sweep at 2 s/query. Interrupt with Ctrl+C
# any time; rerun to resume.
#
# Usage:
#   ruby domain/find_io.rb     # start or resume

require 'socket'
require 'timeout'
require 'set'

WHOIS_HOST     = 'whois.nic.io'.freeze
WHOIS_PORT     = 43
OUTPUT_FILE    = File.join(__dir__, 'io.txt')
STATE_FILE     = File.join(__dir__, 'io_checked.txt')
SLEEP_NORMAL   = 2.0
SLEEP_MAX      = 60.0
MAX_RETRIES    = 3
WHOIS_TIMEOUT  = 15

def log(msg)
  STDERR.puts("[#{Time.now.strftime('%H:%M:%S')}] #{msg}")
end

# Send a WHOIS query for `domain` to whois.nic.io:43 and return the server's
# response as a string. Returns nil on network failure or timeout.
def whois_query(domain)
	Timeout.timeout(WHOIS_TIMEOUT) do
		Socket.tcp(WHOIS_HOST, WHOIS_PORT, connect_timeout: 5) do |sock|
			sock.write("#{domain}\r\n")
			sock.read
		end
	end
rescue StandardError => e
	log("whois error for #{domain}: #{e.class}: #{e.message}")
	nil
end

# Classify a name as :available, :registered, or :error.
def check_domain(name)
	response = whois_query("#{name}.io")
	return :error if response.nil? || response.length < 20

	# Rate-limit / temporary-failure signals — treat as :error so we retry
	return :error if response =~ /rate.?limit|too many|quota|temporarily|try again later/i

	# .io WHOIS server signals for unregistered
	return :available if response =~ /Domain not found|NOT FOUND|No match for|not registered/i

	# Default: assume registered if WHOIS returned a real-looking record
	:registered
end

# Load resume state from prior runs.
checked = Set.new
if File.exist?(STATE_FILE)
	File.readlines(STATE_FILE, chomp: true).each { |line| checked.add(line) }
end

found = Set.new
if File.exist?(OUTPUT_FILE)
	File.readlines(OUTPUT_FILE, chomp: true).each do |line|
		found.add(line.sub(/\.io$/, ''))
	end
end

log("Resuming: #{checked.size} already checked, #{found.size} previously found available")

# Open append handles for both output files.
# .sync = true so partial writes survive Ctrl+C cleanly.
state_io = File.open(STATE_FILE, 'a')
state_io.sync = true
output_io = File.open(OUTPUT_FILE, 'a')
output_io.sync = true

trap('INT') do
	log("Interrupted. State is consistent. Rerun to resume.")
	state_io.close rescue nil
	output_io.close rescue nil
	exit 130
end

processed = 0
('a'..'z').each do |a|
  ('a'..'z').each do |b|
    ('a'..'z').each do |c|
      name = "#{a}#{b}#{c}"
      next if checked.include?(name)

      result = nil
      retries = 0
      loop do
        result = check_domain(name)
        break if result != :error
        retries += 1
        break if retries > MAX_RETRIES
        backoff = [SLEEP_NORMAL * (2**retries), SLEEP_MAX].min
        log("retry #{retries}/#{MAX_RETRIES} for #{name}.io in #{backoff}s")
        sleep(backoff)
      end

      case result
      when :available
        output_io.puts("#{name}.io")
        found.add(name)
        log("AVAILABLE: #{name}.io  (#{found.size} found this run)")
      when :error
        log("giving up on #{name}.io after #{MAX_RETRIES} retries; will retry on next run")
        sleep(SLEEP_NORMAL)
        next # do NOT mark as checked
      end

      state_io.puts(name)
      checked.add(name)
      processed += 1

      log("progress: #{processed} processed this run, #{checked.size} total checked") \
        if processed % 50 == 0

      sleep(SLEEP_NORMAL)
    end
  end
end

log("DONE. Total checked: #{checked.size}, available found: #{found.size}")
state_io.close
output_io.close
