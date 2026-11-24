# Workshop and Spellcheck

Choose **Play** to enter the workshop. To try **Fireball** immediately, choose **Review spellbook** and **Enter sandbox**. Use **Back to Workshop** to return.

## Run on Windows

### From the repository

1. Install Godot 4.7 and make its console executable available as `godot` on PATH. The team build was made with Godot 4.7.2. [Godot downloads](https://godotengine.org/download/windows/)
2. For local sandbox generation, install Ollama and make `ollama` available on PATH. [Ollama for Windows](https://docs.ollama.com/windows)
3. In PowerShell at the repository root, run:

   ```powershell
   Copy-Item .env.example .env
   powershell -ExecutionPolicy Bypass -File .\start-test.ps1
   ```

The launcher reuses or starts Ollama and pulls the selected model when needed. Its default port is `11435`. If the Ollama desktop app is already serving on the usual port, set `SPELLCHECK_OLLAMA_PORT=11434` in `.env` or pass `-Port 11434` to the launcher. Add `-Editor` to launch the editor and start with F5.

### From the Windows team build

1. Extract the ZIP to a writable folder. Keep the executable and its `.pck` together.
2. Copy the supplied `.env.example` to `.env` beside the executable. Use the provider settings below to choose local or hosted generation.
3. To start the game and set up local Ollama, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\start-test.ps1 -GameExe .\Spellcheck.exe
   ```

You can also launch `Spellcheck.exe` directly with a hosted sandbox provider, with a local Ollama server already running on the configured port, or to play with your unlocked spells offline. If you launch directly without a port setting, the game tries `11434`.

### Provider settings

The pipelines have separate provider and model settings. Environment variables override `.env` values. Keep your API keys in your own environment or local `.env`. The launcher skips Ollama when the sandbox uses a hosted provider.

| Pipeline | Provider variable | Model variable | Default |
| --- | --- | --- | --- |
| Workshop element recipe | `WORKSHOP_PROVIDER` | `WORKSHOP_MODEL` | `openrouter` with `openrouter/free` |
| Sandbox spell behavior | `SPELLCHECK_PROVIDER` | `SPELLCHECK_MODEL` | `ollama` with `gemma3:4b` |

| Hosted provider value | Credential variable | Model requirement |
| --- | --- | --- |
| `openrouter` | `OPENROUTER_API_KEY` | The workshop needs an OpenRouter model or route that supports strict structured output. The sandbox needs JSON object mode. |
| `google` | `GEMINI_API_KEY` | Use an AI Studio model ID that supports structured output on the OpenAI-compatible endpoint. |
| `groq` | `GROQ_API_KEY` | Use a Groq model ID that supports JSON object mode. |

For example, to keep the workshop on OpenRouter and send sandbox behavior to Google AI Studio, set `SPELLCHECK_PROVIDER=google`, `SPELLCHECK_MODEL` to your selected Gemini model ID, and `GEMINI_API_KEY` to your own key. Configure the workshop key separately to generate element recipes. [OpenRouter API](https://openrouter.ai/docs/api_reference/overview) · [Google AI Studio compatibility](https://aistudio.google.com/docs/openai) · [Groq structured outputs](https://console.groq.com/docs/structured-outputs)

When the workshop provider is unavailable, the game supplies a built-in element recipe. The QTE still counts. When the sandbox provider is unavailable, earned custom spells stay pending and can be retried. The starter and crafted presets work offline. Text submitted to a hosted pipeline goes to that pipeline's provider.

## Craft and cast

1. Enter a spell name of up to 120 characters. Optionally describe its arena effect in up to 400 characters. For example, name it **Jade Quarry** and describe it as **Turn every rock in the arena green.**
2. Select **Create recipe**. The workshop starts the QTE as soon as the recipe is available. Follow the displayed element keys. **Cancel crafting** abandons the attempt.
3. Win the QTE to earn the spell. A spell appears in the arena only after its behavior also validates. You can keep crafting or enter the arena while that happens. If the behavior fails or you quit before it finishes, return to the workshop and choose **Retry sandbox effect**. An optional clarification updates the sandbox description while keeping the completed recipe and QTE result.
4. In the sandbox, use **WASD** to move and aim with the mouse. Press **B** to open the unlocked book, or **hold Shift**, type the spell name, and **release Shift** to equip. **Left click** to cast. **Inspect** displays the equipped behavior.

**Kamehameha**, **Hollow Purple**, and the other authored presets reuse the shipped behaviors after you craft them under their reserved names or aliases. Each book holds up to ten crafted spells, including earned pending spells. Fireball is a separate starter.

## Spell data and rules

The authored behaviors live in [seed_spellbook.json](seed_spellbook.json). Completed recipes, their QTE results, generated arena definitions, and unlock state share `spellcheck/local/spellbook.json`. The path is relative to the repository during development and the executable in the Windows build. Close the game and move that one file out of the folder to start fresh.

[spell_catalog.gd](spell_catalog.gd) describes the vocabulary and typed schema sent to the model. [spell_intent.gd](spell_intent.gd) compiles validated definitions. [magic_rules.gd](magic_rules.gd) selects the targets and applies the operations. For example, the Jade Quarry behavior can include this rule:

```json
{"event":"CAST","scope":"ARENA","tag":"ROCK","op":"SET","property":"TINT","value":"GREEN"}
```

On cast, the rule selects rocks across the arena and sets their tint to green. The same vocabulary can describe camera saturation, caster speed, afterimages, domain membership, timed effects, particles, and other engine-supported properties.

## Verification

Run these commands from the repository root with the Godot console executable available as `godot`.

```powershell
godot --headless --path . --editor --import
godot --headless --path . res://spellcheck/tests/integration.tscn
godot --headless --path . --script res://Scripts/ai/provider_fixtures.gd
godot --headless --path . --script res://spellcheck/tests/smoke.gd
```

To exercise real sandbox spell generation with Ollama, start Ollama with the launcher or use an existing server with `gemma3:4b` pulled. Set the correct port, then run:

```powershell
$env:SPELLCHECK_PROVIDER = 'ollama'
$env:SPELLCHECK_MODEL = 'gemma3:4b'
$env:SPELLCHECK_OLLAMA_PORT = '11435'
godot --headless --path . --script res://spellcheck/tests/smoke.gd -- --planner
```

The test suites use separate generated save files. The integration test goes from the main menu through crafting and into the arena, where a compiled rule changes a rock.
