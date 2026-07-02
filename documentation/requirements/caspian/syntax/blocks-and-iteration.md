# Blocks and iteration
<!--index: 8-->

~~~vibecode
{"vibecode": {
	"doc": "requirements_caspian_syntax_blocks_and_iteration",
	"role": "spec for Caspian's block form (do ... end), the .each / .times / .upto iteration idioms, and the `as $loop` loop-object binding",
	"audience": "developers writing Caspian; parser implementers"
}}
~~~

Blocks use the `do ... end` shape. Most iteration goes through method calls that take a block:

~~~caspian
$items.each do ($item)
	&puts $item
end

5.times do ($i)
	&puts $i
end

1.upto(10) do ($n)
	&puts $n
end
~~~

Naming a loop with `as $loop` binds a loop object that exposes state and control (`$loop.count`, `$loop.index`, `$loop.break`, `$loop.next`):

~~~caspian
$items.each do ($item) as $loop
	if $loop.count > 5
		$loop.break
	end
end
~~~
