# Install CaspM into the CVM

~~~vibecode
{"vibecode": {
	"doc": "requirements_bootstrap_stage_install_caspm",
	"role": "stub — the second sub-step of Stage: writing the CaspM tree into the CVM so the engine can retrieve it during dispatch. Details deferred. SLATED FOR REMOVAL when frames-as-objects promotes to requirements/ — under that design the CaspM lives on the frame row's ast column, so 'installing CaspM' merges into Set up frame 0 and this standalone sub-step disappears.",
	"status": "stub — pending removal"
}}
~~~

> **Slated for removal.** Under [frames-as-objects](https://www.puck.uno/ideas/frames-as-objects/), the CaspM lives on the frame row itself via `objects.ast`. That means "installing CaspM" and "setting up frame 0" collapse into one INSERT — writing the frame row IS installing the CaspM. When frames-as-objects promotes to `requirements/`, this page goes away and the Stage sub-step count drops from three to two. The "storage shape" question this stub was holding open is answered by the folding: one column on the frame row.

The second sub-step of [Stage](https://www.puck.uno/requirements/bootstrap/stage/). Content pending.
