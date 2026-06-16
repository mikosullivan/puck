# Server-management actor

~~~vibecode
{"vibecode": {
	"doc": "bootstrap_example_server_management_actor",
	"role": "worked example showing the bootstrap pattern used as a script-local actor — a maintenance script manages one specific server through its lifecycle (connect, snapshot, restart, wait, teardown). Demonstrates a bare `bootstrap ... end` form where the object is the script's protagonist for the duration of the work.",
	"audience": "Caspian programmers learning the bootstrap pattern",
	"parent_doc": "index.md (bootstraps concept)"
}}
~~~

A maintenance script manages one specific server through its lifecycle:

~~~caspian
%vibecode
	role: 'manage the one server this script is targeting';
end

$server = bootstrap # server controller
	field :host, class: 'string', required: true, :get, :set
	field :ssh,  class: 'object'

	method &connect()
		@ssh = %net.ssh.new(host: @host)
	end

	method &snapshot()
		@ssh.exec('snapshot-cmd')
	end

	method &restart()
		@ssh.exec('systemctl restart app')
	end

	method &wait_healthy($timeout)
		# poll until healthy or timeout
	end

	method &teardown()
		@ssh.close
	end
end

$server.host = 'app-01.example.com'
$server.connect
$server.snapshot
$server.restart
$server.wait_healthy(timeout: 60)
$server.teardown
~~~

**Why a bootstrap.** The script manages ONE specific server through a sequence of operations. Each method needs the shared SSH connection. State (the connection) is genuinely tied together; methods call related methods. There's no "ServerController" class worth designing — the next script that does similar work will have its own concerns and its own bootstrap. This object is local craft for this maintenance task.

See [bootstraps/index.md](index.md) for the broader pattern.
