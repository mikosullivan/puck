# Script-specific configuration

~~~vibecode
{"vibecode": {
	"doc": "bootstrap_example_script_specific_configuration",
	"role": "worked example showing the bootstrap pattern used for a script's configuration object — a deploy script that needs a handful of values plus a method or two for using them. Demonstrates the bare `bootstrap ... end` form (returns the constructed object, used as-is).",
	"audience": "Caspian programmers learning the bootstrap pattern",
	"parent_doc": "index.md (bootstraps concept)"
}}
~~~

A deployment script needs a handful of configurable values plus a method or two for using them:

~~~caspian
%vibecode
	role: 'the deploy script configuration — one object, used across the script';
end

$config = bootstrap # deploy config
	field :env, class: 'string', default: 'staging'
	field :region, class: 'string', default: 'us-east-1'
	field :max_attempts, class: 'integer', default: 3

	method &endpoint()
		'https://' + @env + '.example.com'
	end

	method &is_production?()
		@env == 'production'
	end
end

# elsewhere in the script:
$client = %net.http_client.new(base_url: $config.endpoint)
if $config.is_production?
	%stdout.puts 'deploying to prod, attempts: ' + $config.max_attempts
end
~~~

**Why a bootstrap.** This is the deploy script's config. It's not a reusable "DeployConfig" type; nobody else needs it. The methods are convenient packaging for "compute the endpoint URL from the env" — a function would work but the object groups the data and the derivations together cleanly.

See [bootstraps/index.md](index.md) for the broader pattern.
