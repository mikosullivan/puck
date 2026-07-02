# Classes
<!--index: 11-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_classes",
	"role": "spec for Caspian's class definition syntax — the nameless `class` keyword, the inline `# label` convention for readability, method definitions inside, and instantiation via `.new()`. Class inheritance has its own sub-page.",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

Class definitions have no name in the language — they're objects assigned to variables. An inline `# label` after the `class` keyword is a convention for readability, since classes don't carry a name syntactically:

~~~caspian
$widget = class # widget
    method &init($name, $rank)
        @name = $name
        @rank = $rank
    end

    method &greet()
        &puts 'hi, ' + @name
    end
end

$w = $widget.new('picard', 'captain')
$w.greet()
~~~

Instantiation is `$class.new(...)`. When the class defines an `&init` method, `.new()` runs it with the supplied arguments after the instance is allocated.

`@name` inside a method reads and writes `%bucket['name']` on the current instance — `@` is the sigil for bucket access.
