> ## Documentation Index
> Fetch the complete documentation index at: https://claude.com/docs/llms.txt
> Use this file to discover all available pages before exploring further.

# Changelog

> Release notes for Claude Desktop

<Update label="v1.30096.1" description="2026-08-13">
  **General**

  * Fixed Find (Cmd+F) doing nothing the first time it was pressed after launch.
  * Fixed right-to-left text in the composer scrambling around embedded left-to-right words; code blocks stay left-to-right.
  * Fixed the Artifacts entry missing from the sidebar on Windows machines that can't run local Cowork; it now opens the Artifacts gallery.
  * Fixed macOS asking for notification permission as soon as the app launched, instead of when the first notification is about to appear.
  * Fixed the app crashing at launch, or on a system theme change, on some Linux installs (most often repackaged builds); it now falls back to a default tray icon.

  **Code**

  * Added Rewind to cloud sessions (message menu, Esc Esc, or `/rewind`), and fixed rewound-away messages reappearing when a rewound cloud or Remote Control session was reopened.
  * Fixed an interrupted Claude Code download (for example, after a crash or power loss mid-install) leaving Code sessions on that computer unable to start, most often on Windows.
  * Fixed an unanswered permission or plan-approval prompt in a cloud session sometimes being treated as approved after the session's environment disconnected.
  * Fixed cloud sessions marked as needing input sometimes opening without the question or approval prompt.
  * Fixed Remote Control sessions sometimes never connecting when opened while idle, staying off your other devices after a stop or interruption until turned back on by hand, and looking idle instead of reporting that the host computer is offline.
  * Fixed copy and paste problems: transcript text pasted into rich-text apps lost the spaces around inline code, bold, and italics and mangled code blocks, and Cmd+C after selecting text in the Plan view copied nothing.

  **Cowork**

  * Fixed the earlier conversation being discarded when you chose Go back after a failed task resume, or edited a message right after the app restarted.
  * Fixed memory saves failing when the Claude Code `managed-settings.json` policy sets `allowManagedPermissionRulesOnly`.
  * Fixed Cowork on Windows failing on every launch with "VM service not running" after its background service had stopped; the service is now restarted automatically, and otherwise the error explains that restarting the computer restores it.
  * Fixed Cowork sometimes pulling you back to the bottom of a task after you had scrolled up, for example when a sub-agent step finished.

  **3P**

  * Added `otlpAuthMode` and `otlpHeadersHelper`, two ways to authenticate telemetry exports without static `otlpHeaders`: set `otlpAuthMode` to `inference-credential` to reuse the signed-in user's inference token, or point `otlpHeadersHelper` at an executable that prints the collector headers as JSON.
  * Added an optional `inferenceGatewayOidc.resource` subfield that sends an RFC 8707 resource indicator on gateway sign-in and token refresh, for identity providers that audience-restrict access tokens.
  * Changed `inferenceBedrockBaseUrl` and `inferenceVertexBaseUrl`: only affects users who entered the bootstrap server URL themselves (in Settings or a local config file). Those users are now asked once to allow a Bedrock or Vertex endpoint that server delivers before it takes effect, the same prompt `inferenceGatewayBaseUrl` already shows. Managed deployments (bootstrap URL set by device management, or `trustBootstrapDelivery: true`) see no change.
  * Changed `claudeAiImport`: an imported session now asks the user to confirm once (Trust and resume) before Claude continues it for the first time; this also applies to sessions imported before this update.
  * Fixed a single malformed `allowedPluginMarketplaces` (beta) entry disabling every configured marketplace; the entry is now skipped and reported.
  * Fixed sending messages failing when a bootstrap server turned Cowork off (`coworkTabEnabled` set to `false`); the home screen now opens directly into Chat.
  * Fixed OpenTelemetry exports being rejected when the configured gateway also serves as the telemetry collector endpoint.
</Update>

<Update label="v1.28929.0" description="2026-08-11">
  **General**

  * Added the standard macOS full-screen keyboard shortcut, with an Enter Full Screen and Exit Full Screen item in the View menu.
  * Fixed a startup error on some Linux systems, most often repackaged or containerized installs, that left the app without a tray icon and recurred on every system theme change.
  * Fixed commands in the built-in terminal failing with error -1743 when controlling other apps on macOS, instead of showing the Automation permission prompt.
  * Fixed sign-in on macOS repeatedly failing with "Failed to login, it may have been cancelled"; Claude now opens the sign-in page in your default browser when the system sign-in sheet is unavailable.
  * Fixed some Windows installs (MSIX packages and enterprise-managed roaming profiles) failing to save chat history, settings, and scheduled tasks, and Cowork failing to start with "Download failed" after an app update.
  * Fixed the app's memory use growing without bound during long-running sessions.

  **Code**

  * Removed the ability for scheduled-task runs and other unattended sessions to start dev servers in the Browser preview; other sessions now approve each distinct dev server command once rather than on every start.
  * Fixed app settings, and the app's record of session worktrees, being discarded when those files had been re-saved with a UTF-8 byte-order mark by an external editor.
  * Fixed forked sessions starting from the original base branch instead of the parent session's current branch.
  * Fixed importing Claude Code CLI sessions changing the order of existing sessions in `claude --resume`.
  * Fixed sessions failing to resume, reporting their conversation history as missing, after Claude had moved the session into a worktree.
  * Fixed file uploads through Claude in Chrome from a Code session failing with "Invalid arguments for tool file\_upload".

  **Cowork**

  * Fixed a follow-up message sent while Claude was still writing a reply sometimes being dropped, with the reply cut off.

  **3P**

  * Added history import. When `claudeAiImport.enabled` is `true`, users can bring a Claude.ai data export, Cowork, Code, and Chat sessions from other Claude installs on the same computer or from an app data folder they choose, and terminal Claude Code sessions into the app from Settings > Import. `claudeAiImport.bannerBehavior` controls an optional banner on new tasks that offers it: `off` (default), `detect` (only when earlier sessions are found on the computer), or `show` (everyone, until dismissed or imported).
  * Added `modelPrefer1mContext`. When `true`, a user who has not yet chosen a model starts on the 1M-context variant of the default model whenever the deployment marks or reports that model as 1M-capable, including auto-discovered models. Saved selections are never changed. Defaults to `false`.
  * Added the gateway address, `inferenceGatewayBaseUrl`, to the one-time bootstrap consent prompt. When a bootstrap server delivers it and the bootstrap URL was not set through device management, each user is asked once at launch to allow the address, and again if it later changes; the app does not connect to the gateway until they choose Allow. Existing installs prompt the first time they start this version. Set `trustBootstrapDelivery` to `true` in your device-management profile or local configuration file to accept it for everyone in advance.
  * Changed the Code tab to be hidden entirely, rather than shown greyed out, when an administrator has disabled Code.
  * Fixed a session opened in a new window on Windows having no title bar, window controls, or drag area.
  * Fixed stored sign-ins being lost when the system keychain was temporarily locked.
  * Fixed the Chat tab ignoring `toolSearchEnabled`, which sent every connector's tool definitions with each request and could exceed the context window when many connectors were configured; Chat now loads them on demand when the key is `true`, as Cowork and Code do.
  * Fixed the credential-expired notice and the session error banners in Cowork and Code offering no way to sign in again when the credential comes from a helper script (`inferenceCredentialHelper`); they now show "Sign in again", which re-runs the helper.
  * Fixed the model picker reverting to the standard-context variant in new sessions, after relaunch, and when switching between Chat and Cowork once the 1M-context variant had been chosen.
</Update>

