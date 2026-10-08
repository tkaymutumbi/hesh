# Using Hesh with Codex and Claude

Hesh includes a local stdio MCP server with no Python dependencies. It uses the
existing user-only Unix socket directly, rather than launching a CLI process for
every action. The Qt browser executes structured DOM operations in Chromium's
isolated application world; no remote debugging port is exposed.

Build Hesh, then register the server (replace the paths with your checkout):

```bash
codex mcp add hesh -- python3 /path/to/hesh/integrations/mcp/hesh_mcp.py --binary /path/to/hesh/build/hesh
claude mcp add --scope user --transport stdio hesh -- python3 /path/to/hesh/integrations/mcp/hesh_mcp.py --binary /path/to/hesh/build/hesh
```

Restart the client or open a new session to discover the tools. The server starts
Hesh in background mode when needed. `--no-autostart` connects to an existing
backend only. CMake installation installs the script as `hesh-mcp` alongside
`hesh`; it can find the installed app on `PATH`.

These commands follow the official [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)
and [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp).
The server supports the MCP initialization protocol versions 2024-11-05,
2025-03-26, 2025-06-18 and 2025-11-25 over
[newline-delimited stdio JSON-RPC](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

## Tools

| Tool | What it does |
| --- | --- |
| `hesh_devices` | List devices and profiles; read device context/presentation; create, preview, navigate, rename, reload, start or stop devices; show the main app |
| `hesh_inspect` | Read current URL, title, visible page text and controls with unique CSS selectors; open a preview and wait for readiness when needed |
| `hesh_interact` | Batch up to 30 clicks, fills, focus or scroll actions and return a fresh snapshot |
| `hesh_memory` | Put, get, list or delete JSON notes shared across clients and restarts |
| `hesh_logins` | List saved accounts or fill one on its matching HTTPS site, without returning its password |

Example requests to the agent:

> Create a Desktop device named My App at https://example.com, open it and inspect the login page.

> Fill the saved login for me, then sign in.

> Save the device id and what you learned under memory key my-app/setup so we can continue tomorrow.

Page text is untrusted website content. Snapshot fields omit input values, and
password fields cannot be filled through the generic interaction tool. Batches
stop at the first error; completed earlier steps are not rolled back. Inspect
again before retrying a failed batch or a timed-out mutation.

## Copy a device prompt

Right-click a device in the sidebar or inside its standalone window, or open the
workspace toolbar's overflow menu. **Copy agent prompt** copies a ready-to-paste
prompt with the device ID, name, profile, current URL, viewport, run state and
whether it is in a standalone window or the main workspace. Add your task at the
end and give it to Codex or Claude.

The menus also include **Copy device ID**, **Saved logins…**, and
**Pause/Resume AI control**. Saved logins selects that menu's device before opening
the dialog. Menus scroll when the window is too short to show every option.

`hesh_devices` with `action: "context"` returns current presentation/visibility
and the same prompt, so an agent can verify copied context before acting.
Device lists include presentation too. Copying a prompt omits any URL user-info.

## Saved logins

Open **Logins** in Hesh's titlebar. Enter an HTTPS site, email/username and
password, then choose **Save**. Select a saved account to fill or delete it.
Filling operates on the selected device's current live browser surface: open its
preview first. Optional CSS selectors support forms without conventional email
or password fields. Agents can use the same saved account via `hesh_logins`.

Passwords are stored through `secret-tool` in the desktop's Secret Service
keyring (typically GNOME Keyring or KWallet). Install `libsecret`/`secret-tool`
and use an unlocked keyring. There is no plaintext password fallback. Passwords
are passed to the helper over stdin, not in process arguments. Hesh stores only
origin and account name in its own metadata file. Secrets enter the matching
page's form and are therefore accessible to that website, as with manual typing.
Hesh does not return them to MCP or submit the form automatically.

Filling requires an exact HTTPS origin match (scheme, hostname and port). A form
that declares a different submission origin is rejected. HTTP sites and
cross-origin iframe forms are unsupported. An unlocked desktop keyring and the
local control socket trust programs running as your Linux user; this feature
is not a security boundary against other programs in the same login session.

## Activity and speed

A small badge shows which client is controlling a device. **Pause** blocks new
agent commands; **Resume** enables them again. Pausing cannot undo an action
already sent to the page. Keyring lookup also checks pause again before filling.
The badge remains briefly after each command so fast operations remain visible.
`Ctrl+Alt+P` toggles pause from either Hesh window.

Use compact inspection rather than screenshots, and batch immediate operations
such as filling two fields and clicking a button. Inspect again after navigation
or asynchronous changes; a batch does not wait for app animations or network
requests between steps. Different devices can run page requests independently;
overlapping requests on the same device return a busy error.

DOM clicks are synthetic. Native file pickers, trusted user gestures, canvas
interfaces, shadow DOM controls, and cross-origin iframes need additional support.
Only Hesh's web devices are implemented; Android emulation remains future work.

Agent memory and account metadata are stored atomically in
`~/.local/share/Hesh/Hesh/automation/state.json` with mode `0600` inside a `0700`
directory. Memory has a 2 MiB limit and is **not encrypted**: use it for notes,
never passwords or tokens. Device browser storage continues to preserve cookies,
local storage and IndexedDB independently.

## Verification

```bash
cmake -B build -S .
cmake --build build -j
ctest --test-dir build --output-on-failure
python3 tests/control_smoke.py build/hesh
python3 tests/mcp_smoke.py build/hesh
```

The MCP test uses temporary settings, an HTTPS fixture, the real Qt WebEngine
and an isolated fake keyring helper. It verifies MCP initialization, schemas,
inspection, batches, credential fill, wrong-origin rejection, password omission,
private file permissions and restart persistence. Its test-only certificate
bypass is never enabled by the MCP server or production app.
