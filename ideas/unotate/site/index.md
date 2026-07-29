# Unotate mock site

~~~vibecode
{"vibecode": {
	"doc": "idea_unotate_site",
	"role": "the Caspian source for the unotate mock site, file by file. This page shows the root file of the site — the entry point Sammy loads to wire up routes and start serving.",
	"status": "in progress — being built up incrementally"
}}
~~~

The root file in the site — `index.casp`. Sammy loads this as the entry point; it constructs the server, registers routes, and starts the accept loop.

<!-- file: index.casp -->
