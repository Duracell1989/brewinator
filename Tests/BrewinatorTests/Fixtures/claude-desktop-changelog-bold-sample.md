> ## Documentation Index
> Fetch the complete documentation index at: https://claude.com/docs/llms.txt
> Use this file to discover all available pages before exploring further.

# Changelog

> Release notes for Claude Desktop

**v3.1623.1**

Bundled Claude Code version: 2.1.304.

**General**

* No user-facing changes.

**Code**

* No user-facing changes.

**Cowork**

* No user-facing changes.

**3P**

* No user-facing changes.

**v3.1623.0**

Bundled Claude Code version: 2.1.304.

**General**

* Added Storage to Settings. It shows the disk space Claude uses and lets you free up space by removing inactive Cowork tasks and Code sessions; a low disk space warning opens it, and so does typing `/storage` in Cowork and Code. Not yet available on third-party deployments.
* Changed the minimum Windows version to Windows 10 version 2004 (build 19041). PCs on an older Windows keep the version of Claude they have, and the Microsoft Store version is unchanged.
* Removed the "Open external link" confirmation for most links to other websites. Third-party deployments keep it.
* Fixed messages that had not finished sending being lost after a reload: a failed or still-uploading first message now returns to New chat, an edited message that failed to send reopens in its edit box, and a notice says when a message wasn't sent.
* Fixed pop-out windows (Projects, Code sessions, side panes) closing for good when you sign in again or the app reloads its window; they now reopen.
* Fixed saving a skill failing, and sessions starting without skills, on Windows when the full path of the app's skills folder has 260 characters or more.
* Fixed the app freezing on macOS when Claude asked for permission to use an app and the system did not provide that app's icon.

**Code**

* (breaking) Changed `disableDesktopLocalSessions` in Claude Code's managed settings so that the text "true" turns off local sessions, as the boolean does; earlier versions ignored the text.
* (breaking) Changed `sshHostAllowlist` in claude.ai admin settings and in Claude Code's managed settings to also cover a session's jump hosts: each `ProxyJump` host, and the host in a `ProxyCommand` written `ssh -W %h:%p host`, must be on each list that is set, by its `HostName`.
* (breaking) Changed local sessions where claude.ai admin settings apply: a Claude Code managed-settings file on the computer that fails to load now keeps Code sessions from starting or resuming on that computer until it is fixed.
* (breaking) Changed local sessions where claude.ai admin settings apply: the local-session ban (`disableDesktopLocalSessions`) in the computer's own Claude Code managed settings now applies too, so Code sessions on that computer no longer start or resume; sessions already running continue.
* (breaking) Changed saved SSH passwords where claude.ai admin settings apply: the saved-password ban (`disableSshSavedPasswords`) in the computer's own Claude Code managed settings now applies too; passwords already saved are kept but are not offered or used.
* (breaking) Changed SSH sessions on macOS and Linux hosts to not start when the host can't report the real location of one of the session's folders. The error says to start a new session from paths with no symbolic links.
* (breaking) Changed SSH sessions to stop starting the MCP servers from your desktop settings on a remote host whose administrator uses Claude Code's `managed-mcp.json` to allow only their own servers.
* (breaking) Changed SSH where claude.ai admin settings apply: hosts missing from `sshHostAllowlist` in the computer's own Claude Code managed settings are refused, whatever admin settings allow. An empty or malformed list turns SSH off; with no list there, only the admin settings list applies.
* (breaking) Changed the Browser pane in SSH sessions to keep sign-ins separate for each session and only until you quit the app, to open localhost (your computer) and private-network addresses only when you type them, and to no longer open intranet sites at public-looking names, even when typed.
* (breaking) Changed WSL sessions, and SSH sessions on macOS and Linux hosts, to stop using an added folder whose saved path is relative, starts with `//`, or starts or ends with a space, the next time the session starts. The folder stays listed in the session.
* Removed "Download file" for script files such as .js, .bat and .ps1 shown as text in SSH, WSL, cloud and Remote Control sessions; Copy file contents remains.
* Fixed an app update or restart ending work on an SSH host: sessions in the Windows app now carry on with a task still running on the host instead of starting it afresh, and on macOS and Linux a restart after an update no longer ends a task, or drops a permission prompt, older than three days.
* Fixed messages queued or sent in a local session while Claude was working being lost when the app quit, updated or crashed; they now come back at the next launch, held until you send them.
* Fixed removing an inactive session's worktree, from Settings or through Claude, also deleting an archived session's worktree nested inside it, including uncommitted changes; both are now kept, and a worktree that gains uncommitted changes after a clean preview is kept too.
* Fixed SSH sessions in the macOS and Linux apps failing to connect to servers that allow only one session per connection (`MaxSessions 1`). The app now signs in separately for each connection it opens there, so a server that asks for a one-time code at every sign-in asks more than once.
* Fixed the automatic local cleanup deleting a session's Remote Control conversation on claude.ai, for organizations with the Claude Code + Cowork HIPAA configuration; the conversation is now archived.

**Cowork**

* Added a Hand off to Claude Code option to the menu under a design's name. It opens Claude Code with a prompt to build the design in your codebase, or gives you the prompt to paste.
* Changed the import from Claude (third-party) where device management turned it on: a copied Cowork task or project now keeps an attached home, Documents or `~/Claude` folder. Folders above home and system folders such as `~/Library` or `AppData` are still left out.
* Fixed global instructions sometimes reverting to an earlier version after an older task was archived, deleted, cleaned up or continued.
* Fixed recently opened tasks being removed by the automatic local cleanup after an app restart, for organizations with the Claude Code + Cowork HIPAA configuration.
* Fixed the folder picker sometimes showing "Couldn't load" until the page was reloaded.

**3P**

* Added `quickEntryDefaultShortcut`, which sets the Quick Entry shortcut, or `off` for none, for users who have not chosen their own in Settings.
* Added `releaseChannel`. Set it to `staggered` to have devices update to releases that Anthropic marks after they have fully rolled out on `stable`; those devices skip the releases in between, and fixes reach them later.
* Added an optional `icon` to remote and local `managedMcpServers` entries, a PNG or JPEG image as a base64 `data:` URI of up to 4,096 characters, shown so users can tell connectors apart.
* Added nested sessions to local and SSH sessions in the Code tab: Claude can start a task in a separate session, which appears under the original session in the sidebar and reports back to it. Each nested session sends its own requests to your inference provider.
* Added the new Code tab: the New session page with saved environments (folders and SSH hosts), the session rail, sidebar grouping by environment, and the pickers under the message box. Anthropic-hosted cloud environments, Remote Control, voice input and worktrees for extra folders remain unavailable.
* Added to Code tab sessions Claude's plan and a next-step box at the end of a turn, suggested next actions, `/btw` side chats in a pane, and permission requests, questions and suggested tasks shown in the conversation.
* (breaking) Changed `sshHostAllowlist` (beta) to also cover a session's jump hosts: each `ProxyJump` host, and the host in a `ProxyCommand` written `ssh -W %h:%p host`, must be on the list by its `HostName`. The error on a refused session names the host to add.
* Changed "Sign in with Claude Console" to keep your sign-in instead of creating an API key in your organization. The app keeps using a key created by an earlier version until you next sign in.
* Changed `builtinToolPolicy` to accept every built-in tool name Claude Code publishes, so an entry for a tool such as `CronCreate` or `LSP` is no longer dropped.
* Changed `isLocalDevMcpEnabled`: `false` also stops local MCP servers from plugins (your organization's marketplaces included), from Claude Code's `managed-mcp.json` if they use `${VAR}`, and in Code from Claude Code's own configuration files. Remote and org-plugins directory servers still run.
* Changed subagents in Code tab sessions to run in the background even when Claude asks for the foreground, so they keep running after Stop; Claude can also now start a fork of the conversation as a subagent.
* Changed the restart when a device-management profile that sets more than the app-behavior keys first applies while the app runs on a user's own saved configuration: the dialog appears right away, not after `relaunchEnforcementHours`.
* Fixed "Or sign in with Claude.ai" leaving "Couldn't connect to Claude" at every launch where claude.ai is blocked: a launch with nobody signed in to Claude.ai now returns to the organization's sign-in page. On managed devices the error screen also has a "Sign in with your organization" button.
* Fixed Claude in Cowork being told to save its work in a connected folder under an `allowedWorkspaceFolders` entry whose `mode` is `ro`. Claude is now told which folders are read-only and to save new files and edited copies in a writable connected folder or, if there is none, the outputs folder.
* Fixed importing the same folder or exported zip again from Settings > Import & export creating a second copy of every session. Repeating an import made with an earlier version still copies its sessions once more, and a folder on a network share or mapped drive is copied each time.
* Fixed the environment variables editor failing to open or save, plugin command permissions being forgotten at every restart, and adding a project's folders again not restoring Chat's access to them, after the app's data folder was moved to another computer or the system keychain was reset.

