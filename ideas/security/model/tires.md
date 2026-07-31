# Worked example: tire manufacturing

~~~vibecode
{"vibecode": {
	"doc": "ideas_security_model_tires",
	"role": "worked example applying the five security rules to a tire manufacturing simulator — the real-world scenario that stress-tested the model during design. Shows the role tree that emerges, walks a tire through the process, and traces which rule authorizes each step.",
	"status": "example — accompanies the [model](https://puck.uno/requirements/security/model/) rules; illustrative, not normative",
	"context": "the sim comes from Miko's father, who programmed tire manufacturing simulators in COBOL. Caspian's security model was iterated against this shape until the friction dissolved."
}}
~~~

The manufacturing sim tracks tires as they move through independently-authored stages — oven, post-fire, boxing, sale. Each stage adds its own methods to the tire; the tire is one object throughout but its capabilities change per stage.

## The scenario

The developer wants:

- A **factory** class that orchestrates the whole process. Imported from a URL.
- A **database** class that fetches tires from persistent storage. Imported from a different URL.
- Per-stage classes (`OvenStage`, `PostFireStage`, `BoxStage`, etc.), each authored independently. Imported.
- Tires flow: fetched from the database, sent through each stage, released.

Each stage's team wants to add the methods it needs (`.temperature`, `.price`, `.rigidity`, whatever) without a central schema meeting.

## Setup and role tree

```caspian
# Running as user:
$net_broker = %net.broker.new(host:'db.example.com', port:'5432')
$factory    = %fetch('example.com/factory.casp').new(net: $net_broker)
$factory.run()
```

That produces this role tree:

```
user                              ← root, has %net (Rule 5)
└── R_factory_class               ← fresh from %fetch
```

(R_db_class doesn't exist yet — it's minted later, inside `$factory.run()`, when factory does its own `%fetch`.)

**Rule 5** granted `%net` only to user. User constructed `$net_broker` (an ordinary user-owned object, not a role — `.new` doesn't create roles, only downloads do) and passed it into `$factory`. Factory has no ambient `%net`; it can only reach the network through `$net_broker`.

**Rule 1** applies at every construction: each object gets owned by the role of the frame that created it. `$net_broker` is user-owned (created directly in user's frame). `$factory` is R_factory_class-owned: `.new` dispatches on the fetched class and runs in R_factory_class per Rule 3, so the instance is created in that frame.

## A tire moves through the process

Inside `$factory.run()` (which is running as R_factory_class per Rule 3):

```caspian
method &run()
    $db = %fetch('example.com/db.casp').new(net: @network)

    while $tire = $db.next_tire
        &oven      $tire
        &post_fire $tire
        &box       $tire
    end
end
```

Trace:

- `$db = %fetch(...).new(...)` — `.new` dispatches on the fetched class; per Rule 3 it runs in R_db_class. The constructed `$db` is R_db_class-owned (creating frame's role). **R_db_class becomes a child of R_factory_class**, because R_factory_class's frame is what pulled it in.
- `$db.next_tire` — dispatches on `$db`; per Rule 3 runs in R_db_class. The tire the method returns is constructed inside R_db_class's frame → **owned by R_db_class**. Each tire minted this way ends up as a child of R_db_class (Rule 2's tree grows deeper).
- `&oven $tire` — `&oven` is a function (or class instance) fetched separately by the sim. Its code runs in its own definer's role, R_oven (per Rule 3). `$tire` inside `&oven` is still R_db_class-owned; ownership doesn't transfer when a value is passed as an argument.

The tree now looks like:

```
user
└── R_factory_class
    ├── R_db_class
    │   ├── R_tire_1
    │   └── R_tire_2
    ├── R_oven
    ├── R_post_fire
    └── R_box
```

## The stack-extension question

Each stage's team wants to add methods to the tire — `.temperature` post-oven, `.rigidity` post-fire, `.price` at sale. The natural code:

```caspian
function &post_fire($tire)
    $post_fire_class = %('example.com/post_fire.casp')

    $tire.obj.classes.ensure($post_fire_class) do
        $tire.temperature
        $tire.rigidity
    end
end
```

Under **Rule 2**, structural mutation on `$tire` is authorized only for the tire's owning role or any of its ancestors. The tire is R_db_class-owned. Its ancestors are R_factory_class and user. `&post_fire` runs as R_post_fire (per Rule 3) — sibling of R_db_class, not ancestor. So the `.obj.classes.ensure` call raises.

There are two clean patterns for making this work.

### Pattern A: factory does the ensure, calls the function inside

Factory has ancestral authority over the tire (R_factory_class is R_db_class's parent per Rule 2). Factory does the stack extension itself:

```caspian
method &run()
    $db              = %fetch('example.com/db.casp').new(net: @network)
    $oven_class      = %('example.com/oven.casp')
    $post_fire_class = %('example.com/post_fire.casp')

    while $tire = $db.next_tire
        $tire.obj.classes.ensure($oven_class) do
            &oven $tire
        end

        $tire.obj.classes.ensure($post_fire_class) do
            &post_fire $tire
        end
        # ...
    end
end
```

Factory's frame runs as R_factory_class. R_factory_class is an ancestor of the tire's owning role (R_db_class). Rule 2 allows the mutation. Inside the block, `&post_fire` runs as R_post_fire and finds the tire already carrying its stage methods.

### Pattern B: factory delegates its authority to each stage

Factory delegates its permissions to the stage role for the duration of the stage call. Since factory has ancestral authority over R_db_class (the tire's owning role), delegating that authority to R_post_fire gives R_post_fire the ability to mutate the tire directly for the block:

```caspian
method &run()
    $db = %fetch('example.com/db.casp').new(net: @network)

    while $tire = $db.next_tire
        %role.delegate_to(R_post_fire) do
            &post_fire $tire
        end
    end
end
```

Inside `&post_fire` (running as R_post_fire per Rule 3), R_post_fire temporarily has factory's authority — including the ancestral reach over R_db_class-owned tires. The original block-form `.obj.classes.ensure` code works because R_post_fire is transiently authorized. When the outer block exits, R_post_fire's permissions revert.

Pattern A keeps stages simple (functions operating on already-configured tires); Pattern B keeps stage code self-contained (each stage manages its own additions). Either is legal under the model.

## What the rules did

- **Rule 1** placed every object with an owning role at creation. No ambiguity.
- **Rule 2** made the whole cascade automatic once the initial setup was done. Factory got authority over tires transitively because the DB was created in factory's frame. User has authority over everything because user is at the top.
- **Rule 3** kept downloaded code in its own role — R_post_fire can't accidentally use user's `%net` just because it's operating on a tire user's tree contains.
- **Rule 4** made the ordinary case invisible: any frame that holds `$tire` can call `.temperature` on it. No permissions dialog, no capability check for the common case.
- **Rule 5** made the whole thing possible in the first place: user has `%net` only because the engine handed it in, and every downstream network-user got it via an explicit pass.

Five rules, and the sim works.
