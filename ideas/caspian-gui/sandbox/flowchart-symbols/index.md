# Flowchart symbols sandbox

Play area for using the standard [flowchart symbols](https://www.puck.uno/ideas/caspian-gui/prior-art/flowchart-symbols/) to mock up Caspian program shapes.

## Greet by name

A short Caspian script rendered as a flowchart:

~~~caspian
$name = %stdin.read_line

if $name.empty?
    puts 'Hello, stranger'
else
    puts "Hello, {$name}"
end
~~~

![Flowchart of the greet-by-name script: Start oval → I/O parallelogram reading $name from stdin → decision rhombus asking $name.empty? → Yes branch prints 'Hello, stranger', No branch prints 'Hello, {$name}' → both converge on the End oval. Pastel fills, soft drop shadows, curved merge arrows.](./greet.svg)

**Shapes used** — terminator (rounded oval) for Start / End; I/O (parallelogram) for reading from stdin and printing with puts; decision (rhombus) for the `.empty?` check.

**Styling** — coral fill for terminators, blue for I/O, amber for decision; a soft drop shadow on every shape so the diagram reads like objects on a page instead of ink on a whiteboard; curved arrows on the merge into End rather than sharp elbows; monospace text inside code shapes; italic Yes / No labels next to the decision branches.

Room to iterate — try a horizontal layout, try smaller shapes, try a dark-mode variant, try hand-drawn character (rougher lines, non-uniform fills).
