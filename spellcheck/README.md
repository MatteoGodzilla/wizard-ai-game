# Spellcheck sandbox

Move with **WASD** and aim with the mouse. **Hold Shift** while typing a spell name or short description, then **release Shift** to prepare it. **Left click** to cast once it is equipped. Press **B** to browse or add spells manually. **Escape** cancels typing.

## Launch Spellcheck on Windows

Open PowerShell in the repository root, where `project.godot` lives. Use Godot 4.7 (tested with 4.7.2) and Ollama. All eight presets and previously cached spells work offline. For an offline session, skip steps 1 and 2 and run the Godot command in step 3.

1. **Start the local Ollama server.** If the Windows Ollama app is already serving on port `11434`, use that process. Otherwise, start the server in a separate PowerShell window and leave it open. [Ollama for Windows](https://docs.ollama.com/windows)

   ```powershell
   $env:OLLAMA_HOST = '127.0.0.1:11434'
   ollama serve
   ```

2. **Download the models.** Back in the project PowerShell window, point the Ollama CLI at the same server and pull Gemma 3 4B. Laya is an optional fallback for simple saved projectile descriptions when the server reports that Gemma is missing. Laya requires Ollama 0.40.0 or later. [Laya model documentation](https://ollama.com/library/laya)

   ```powershell
   $env:OLLAMA_HOST = '127.0.0.1:11434'
   ollama pull gemma3:4b
   # Optional fallback
   ollama pull laya:421m-typed-decisions-bf16
   ollama list
   ```

3. **Launch the arena.** Set the same port for Spellcheck before starting Godot. These commands assume `godot` is on your PATH. If you use a downloaded executable, replace `godot` with `& 'C:\path\to\Godot.exe'`. For editor play, run `godot --editor --path .` in the same PowerShell window and press **F5**.

   ```powershell
   $env:SPELLCHECK_OLLAMA_PORT = '11434'
   godot --path . res://spellcheck/sandbox.tscn
   ```

   For a standalone Ollama server on port `11435`, use `11435` in both `OLLAMA_HOST` and `SPELLCHECK_OLLAMA_PORT`. The game connects to `127.0.0.1` and uses `11434` when the port setting is absent. Restart Godot after changing the port so the editor and game inherit it. [Ollama server configuration](https://docs.ollama.com/faq#how-do-i-configure-ollama-server)

4. **Check the setup.** Equip **Fireball** for an offline preset, then type a new request such as **Make every rock green** and check **Inspect** for the **Gemma** source. Equipping the same resolved request again should display **Cache**. Ollama loads the models when Godot asks for a spell.

## Class demo

1. Type **Kamehameha** and click. Energy converges around the wizard during the charge, then the beam fires. Try **lightning** for a branching arc and **soundwave** for an expanding ripple that keeps moving as it fades.
2. Type **Crimson wasteland around me where everything moves slowly except me**. Cast to see an enclosing field. **Inspect** shows the membership rule and the chosen speed multiplier. Projectiles recover their speed when they leave.
3. Try **Turn all the trees in the arena upside down**, then **Make all trees in the arena explode**. Both apply a rule across the arena at cast time. **Reset world** brings the trees back.
4. Cast **Fireball** at the tree by the clearing to watch the fire spread to nearby grass. Try **Clear the scorch from all grass**. **Hollow Purple** still pierces destructible props along its path.
5. Try **Blue bolt on a helix with red shards moving upward at the target on hit**. Inspect the trajectory and the independently configured impact particles.
6. Try **Grow a tree where I point** and click open ground. **Stop Time** pauses the arena and turns the view black and white. Try **Make the camera view black and white for two seconds** for the same filter by itself.
7. Try **Laser Vision** and strafe while firing. Two beams start at the wizard's eyes and follow the caster during the shot. **Two red sine beams diverging 8 degrees** combines a curved path with two separately aimed rays.
8. Press **B** and create a spell with an original name and the description **It works like David's Sandevistan from Cyberpunk: Edgerunners.** Prepare it by name, inspect the generated rules, then click and move. Compare it with a spell that explicitly asks to speed up the caster, slow the world, and leave a rainbow trail.
9. Walk toward the river on the east side. Cross at the bridge, cast **Levitate**, or try **Freeze river water within six meters of me into walkable ice for four seconds** from the bank. **Snowgrave** freezes water in its domain and damages nearby props. **Aqua** extinguishes burning wood and grass on impact.

Gemma receives a compact catalog of engine capabilities and a JSON Schema. It chooses the form, rules, and visuals in one response, with one repair attempt for invalid output. For custom entries it reads the saved description alone, so an arbitrary name can be used to equip the spell. Unintelligible text receives a message in the arena. New entries and validated interpretations are saved to `user://spellcheck_spellbook_v1.json`. Older generations are rebuilt on next equip, with names and descriptions retained.

### Spell vocabulary

- Rules run at cast, hit, entry, exit, interval, or expiration. They select the caster, an impacted object, a member crossing a domain boundary, nearby or enclosed targets, or the whole arena. Tags can distinguish trees, rocks, timber, grass, projectiles, and burning or scorched terrain.
- The forest exposes prop tint, rotation, scale, material and integrity, caster and projectile speed, caster hover, arena time, and terrain heat, burning and scorch. Tree placement creates a normal arena prop at the aim point. Timed property edits and membership effects revert independently. World mutations last until another spell changes them or the arena is reset.
- Camera rules use `SCREEN_SATURATION` from 0 (black and white) to 2 (vivid). The HUD retains its colors. Caster rules use `AFTERIMAGE` with a palette color, `SPELL`, `RAINBOW` or `OFF`. Stop Time combines two rules with matching durations through its reference description in the seed data.
- Particle anchors follow the caster or spell, or use the aim or hit point. Profiles select phase, color, direction, shape, speed, size and count. Straight, sine, cosine, helix and zigzag paths use engine-authored math. Charges run from 0 to 3 seconds.
- Beams can use 1–4 rays with independent spacing and a symmetric angular spread. They follow the caster's movement and keep the firing direction selected at cast time.
- `WATER` selects river cells in either state, and `ICE` selects the frozen ones. `TRANSFORM MATERIAL` changes traversability. Timed `WET` status puts out fire and prevents reignition while it lasts.

Charge is opt-in through the prompt or spellbook description. Kamehameha and Hollow Purple describe a wind-up. A short unregistered name such as **DD** needs a full spell name or a description. You can save a two-letter spell with a description in the spellbook.

## Run verification

With Godot’s console binary available as `godot`, run these from the project root.

```powershell
$env:SPELLCHECK_OLLAMA_PORT = '1'
godot --headless --path . --script res://spellcheck/tests/smoke.gd

$env:SPELLCHECK_OLLAMA_PORT = '11435' # Use the port of your running Ollama server.
godot --headless --path . --script res://spellcheck/tests/smoke.gd -- --live
```

The test uses a separate save file. It covers offline presets, cache migration, fire and wetness, walking across the river, overlapping ice effects, and world reset. The live suite also exercises reference and plain-language generation, timing, particles, and cache reload with Ollama unavailable. Use `-- --planner` to run just the main live planner cases after the runtime checks.
