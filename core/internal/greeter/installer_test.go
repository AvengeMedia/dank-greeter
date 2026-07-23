package greeter

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestEnsureGreeterCacheSELinuxContext(t *testing.T) {
	t.Parallel()

	t.Run("skips when SELinux is not enforcing", func(t *testing.T) {
		t.Parallel()
		var commands []string
		deps := cacheSELinuxDeps{
			isEnforcing:   func() bool { return false },
			commandExists: func(string) bool { return true },
			run: func(_ string, command string, _ ...string) error {
				commands = append(commands, command)
				return nil
			},
			runQuiet: func(_ string, command string, _ ...string) error {
				commands = append(commands, command)
				return nil
			},
		}
		if err := ensureGreeterCacheSELinuxContext(GreeterCacheDir, func(string) {}, "", deps); err != nil {
			t.Fatalf("ensureGreeterCacheSELinuxContext returned error: %v", err)
		}
		if len(commands) != 0 {
			t.Fatalf("ran commands with SELinux disabled: %v", commands)
		}
	})

	t.Run("repairs missing mapping before restorecon", func(t *testing.T) {
		t.Parallel()
		var commands []string
		run := func(_ string, command string, args ...string) error {
			call := strings.Join(append([]string{command}, args...), " ")
			commands = append(commands, call)
			if strings.Contains(call, "fcontext -m") {
				return errors.New("mapping does not exist")
			}
			return nil
		}
		deps := cacheSELinuxDeps{
			isEnforcing:   func() bool { return true },
			commandExists: func(string) bool { return true },
			run:           run,
			runQuiet:      run,
		}
		if err := ensureGreeterCacheSELinuxContext(GreeterCacheDir, func(string) {}, "", deps); err != nil {
			t.Fatalf("ensureGreeterCacheSELinuxContext returned error: %v", err)
		}
		want := []string{
			"semanage fcontext -m -t cache_home_t /var/cache/dms-greeter(/.*)?",
			"semanage fcontext -a -t cache_home_t /var/cache/dms-greeter(/.*)?",
			"restorecon -R /var/cache/dms-greeter",
		}
		if strings.Join(commands, "\n") != strings.Join(want, "\n") {
			t.Fatalf("commands:\n%s\nwant:\n%s", strings.Join(commands, "\n"), strings.Join(want, "\n"))
		}
	})

	t.Run("uses existing mapping without adding it again", func(t *testing.T) {
		t.Parallel()
		var commands []string
		run := func(_ string, command string, args ...string) error {
			commands = append(commands, strings.Join(append([]string{command}, args...), " "))
			return nil
		}
		deps := cacheSELinuxDeps{
			isEnforcing:   func() bool { return true },
			commandExists: func(string) bool { return true },
			run:           run,
			runQuiet:      run,
		}
		if err := ensureGreeterCacheSELinuxContext(GreeterCacheDir, func(string) {}, "", deps); err != nil {
			t.Fatalf("ensureGreeterCacheSELinuxContext returned error: %v", err)
		}
		if len(commands) != 2 || !strings.Contains(commands[0], "fcontext -m") || !strings.HasPrefix(commands[1], "restorecon ") {
			t.Fatalf("unexpected command sequence: %v", commands)
		}
	})

	t.Run("does not relabel when mapping repair fails", func(t *testing.T) {
		t.Parallel()
		var restoreCalled bool
		run := func(_ string, command string, _ ...string) error {
			if command == "restorecon" {
				restoreCalled = true
				return nil
			}
			return errors.New("semanage failed")
		}
		deps := cacheSELinuxDeps{
			isEnforcing:   func() bool { return true },
			commandExists: func(string) bool { return true },
			run:           run,
			runQuiet:      run,
		}
		if err := ensureGreeterCacheSELinuxContext(GreeterCacheDir, func(string) {}, "", deps); err == nil {
			t.Fatal("expected mapping repair error")
		}
		if restoreCalled {
			t.Fatal("restorecon ran without a persistent mapping")
		}
	})
}

func TestInstallLocalGreeterBinary(t *testing.T) {
	t.Parallel()

	t.Run("installs without replacing packaged binary and restores SELinux label", func(t *testing.T) {
		t.Parallel()
		var commands []string
		deps := localGreeterInstallDeps{
			isEnforcing:   func() bool { return true },
			commandExists: func(string) bool { return true },
			run: func(_ string, command string, args ...string) error {
				commands = append(commands, strings.Join(append([]string{command}, args...), " "))
				return nil
			},
		}

		got, err := installLocalGreeterBinary("/checkout/core/bin/dms-greeter-local", func(string) {}, "", deps)
		if err != nil {
			t.Fatalf("installLocalGreeterBinary returned error: %v", err)
		}
		if got != LocalGreeterBinaryPath {
			t.Fatalf("installed path = %q, want %q", got, LocalGreeterBinaryPath)
		}
		want := []string{
			"install -D -m 0755 /checkout/core/bin/dms-greeter-local /usr/local/bin/dms-greeter-local",
			"restorecon -v /usr/local/bin/dms-greeter-local",
		}
		if !reflect.DeepEqual(commands, want) {
			t.Fatalf("commands = %v, want %v", commands, want)
		}
	})

	t.Run("fails before install when enforcing system cannot label binary", func(t *testing.T) {
		t.Parallel()
		runCalled := false
		deps := localGreeterInstallDeps{
			isEnforcing:   func() bool { return true },
			commandExists: func(string) bool { return false },
			run: func(string, string, ...string) error {
				runCalled = true
				return nil
			},
		}

		if _, err := installLocalGreeterBinary("/tmp/local", func(string) {}, "", deps); err == nil {
			t.Fatal("expected missing restorecon error")
		}
		if runCalled {
			t.Fatal("install ran before SELinux prerequisites were validated")
		}
	})
}

func writeTestFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("failed to create parent dir for %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("failed to write %s: %v", path, err)
	}
}

func TestResolveGreeterThemeSyncState(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name                    string
		settingsJSON            string
		sessionJSON             string
		wantSourcePath          string
		wantResolvedWallpaper   string
		wantDynamicOverrideUsed bool
	}{
		{
			name: "dynamic theme with greeter wallpaper override uses generated greeter colors",
			settingsJSON: `{
  "currentThemeName": "dynamic",
  "greeterWallpaperPath": "Pictures/blue.jpg",
  "matugenScheme": "scheme-tonal-spot",
  "iconTheme": "Papirus"
}`,
			sessionJSON:             `{"isLightMode":true}`,
			wantSourcePath:          filepath.Join(".cache", "DankMaterialShell", "greeter-colors", "dms-colors.json"),
			wantResolvedWallpaper:   filepath.Join("Pictures", "blue.jpg"),
			wantDynamicOverrideUsed: true,
		},
		{
			name: "dynamic theme without override uses desktop colors",
			settingsJSON: `{
  "currentThemeName": "dynamic",
  "greeterWallpaperPath": ""
}`,
			sessionJSON:             `{"isLightMode":false}`,
			wantSourcePath:          filepath.Join(".cache", "DankMaterialShell", "dms-colors.json"),
			wantResolvedWallpaper:   "",
			wantDynamicOverrideUsed: false,
		},
		{
			name: "non-dynamic theme keeps desktop colors even with override wallpaper",
			settingsJSON: `{
  "currentThemeName": "purple",
  "greeterWallpaperPath": "/tmp/blue.jpg"
}`,
			sessionJSON:             `{"isLightMode":false}`,
			wantSourcePath:          filepath.Join(".cache", "DankMaterialShell", "dms-colors.json"),
			wantResolvedWallpaper:   "/tmp/blue.jpg",
			wantDynamicOverrideUsed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			homeDir := t.TempDir()
			writeTestFile(t, filepath.Join(homeDir, ".config", "DankMaterialShell", "settings.json"), tt.settingsJSON)
			writeTestFile(t, filepath.Join(homeDir, ".local", "state", "DankMaterialShell", "session.json"), tt.sessionJSON)

			state, err := resolveGreeterThemeSyncState(homeDir)
			if err != nil {
				t.Fatalf("resolveGreeterThemeSyncState returned error: %v", err)
			}

			if got := state.effectiveColorsSource(homeDir); got != filepath.Join(homeDir, tt.wantSourcePath) {
				t.Fatalf("effectiveColorsSource = %q, want %q", got, filepath.Join(homeDir, tt.wantSourcePath))
			}

			wantResolvedWallpaper := tt.wantResolvedWallpaper
			if wantResolvedWallpaper != "" && !filepath.IsAbs(wantResolvedWallpaper) {
				wantResolvedWallpaper = filepath.Join(homeDir, wantResolvedWallpaper)
			}
			if state.ResolvedGreeterWallpaperPath != wantResolvedWallpaper {
				t.Fatalf("ResolvedGreeterWallpaperPath = %q, want %q", state.ResolvedGreeterWallpaperPath, wantResolvedWallpaper)
			}

			if state.UsesDynamicWallpaperOverride != tt.wantDynamicOverrideUsed {
				t.Fatalf("UsesDynamicWallpaperOverride = %v, want %v", state.UsesDynamicWallpaperOverride, tt.wantDynamicOverrideUsed)
			}
		})
	}
}

func TestUpsertInitialSession(t *testing.T) {
	t.Parallel()

	baseConfig := `[terminal]
vt = 1

[default_session]
user = "greeter"
command = "/usr/bin/dms-greeter --command niri"
`

	t.Run("inserts initial session", func(t *testing.T) {
		t.Parallel()
		got := upsertInitialSession(baseConfig, "alice", "/var/cache/dms-greeter", true)
		if !strings.Contains(got, "[initial_session]") {
			t.Fatalf("expected [initial_session] section, got:\n%s", got)
		}
		if !strings.Contains(got, `user = "alice"`) {
			t.Fatalf("expected alice user in initial session, got:\n%s", got)
		}
		if !strings.Contains(got, `launch-session --from-memory --cache-dir`) {
			t.Fatalf("expected stable launch-session command, got:\n%s", got)
		}
		if !strings.Contains(got, "dms-greeter") {
			t.Fatalf("expected dms-greeter launcher in initial session, got:\n%s", got)
		}
		if strings.Contains(got, `exec niri`) {
			t.Fatalf("initial session must not bake the desktop Exec command, got:\n%s", got)
		}
	})

	t.Run("updates existing initial session", func(t *testing.T) {
		t.Parallel()
		existing := baseConfig + `
[initial_session]
user = "bob"
command = "old-command"
`
		got := upsertInitialSession(existing, "alice", "/var/cache/dms-greeter", true)
		if strings.Contains(got, `user = "bob"`) {
			t.Fatalf("expected bob to be replaced, got:\n%s", got)
		}
		if !strings.Contains(got, `launch-session --from-memory`) {
			t.Fatalf("expected launch-session command, got:\n%s", got)
		}
	})

	t.Run("removes initial session when disabled", func(t *testing.T) {
		t.Parallel()
		existing := baseConfig + `
[initial_session]
user = "alice"
command = "niri"
`
		got := upsertInitialSession(existing, "", "", false)
		if strings.Contains(got, "[initial_session]") {
			t.Fatalf("expected initial session removed, got:\n%s", got)
		}
		if !strings.Contains(got, "[default_session]") {
			t.Fatalf("expected default session preserved, got:\n%s", got)
		}
	})
}

func TestBuildGreetdCommand(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name          string
		greeterCmd    string
		compositor    string
		shellDir      string
		useVoidLogind bool
		want          string
	}{
		{
			name:       "standard command",
			greeterCmd: "/usr/bin/dms-greeter",
			compositor: "Niri",
			want:       "/usr/bin/dms-greeter --command niri --cache-dir /var/cache/dms-greeter",
		},
		{
			name:          "void selects elogind and keeps custom shell dir",
			greeterCmd:    "/usr/bin/dms-greeter",
			compositor:    "Niri",
			shellDir:      "/home/dev/dank-greeter/quickshell",
			useVoidLogind: true,
			want:          "env LIBSEAT_BACKEND=logind DMS_VOID=1 /usr/bin/dms-greeter --command niri --cache-dir /var/cache/dms-greeter -c /home/dev/dank-greeter/quickshell",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			if got := buildGreetdCommand(tt.greeterCmd, tt.compositor, tt.shellDir, tt.useVoidLogind); got != tt.want {
				t.Fatalf("buildGreetdCommand() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestVoidLogindGreeterCommand(t *testing.T) {
	t.Parallel()

	const oldCommand = "/usr/bin/dms-greeter --command niri -C /etc/greetd/niri.kdl"
	const want = "env LIBSEAT_BACKEND=logind DMS_VOID=1 " + oldCommand
	if got := voidLogindGreeterCommand(oldCommand); got != want {
		t.Fatalf("voidLogindGreeterCommand() = %q, want %q", got, want)
	}
	if got := voidLogindGreeterCommand(want); got != want {
		t.Fatalf("voidLogindGreeterCommand() must be idempotent, got %q", got)
	}
}

func TestResolveGreeterAutoLoginState(t *testing.T) {
	t.Parallel()

	cacheDir := t.TempDir()
	homeDir := t.TempDir()

	writeTestFile(t, filepath.Join(cacheDir, "settings.json"), `{
  "greeterAutoLogin": true,
  "greeterRememberLastUser": true,
  "greeterRememberLastSession": true
}`)
	writeTestFile(t, filepath.Join(cacheDir, ".local/state/memory.json"), `{
  "lastSuccessfulUser": "alice",
  "lastSessionDesktopId": "niri.desktop"
}`)

	enabled, loginUser, sessionID, err := resolveGreeterAutoLoginState(cacheDir, homeDir)
	if err != nil {
		t.Fatalf("resolveGreeterAutoLoginState returned error: %v", err)
	}
	if !enabled || loginUser != "alice" || sessionID != "niri.desktop" {
		t.Fatalf("got enabled=%v user=%q session=%q", enabled, loginUser, sessionID)
	}
}

func TestResolveGreeterAutoLoginStateIgnoresStaleSessionExec(t *testing.T) {
	t.Parallel()

	cacheDir := t.TempDir()
	homeDir := t.TempDir()

	writeTestFile(t, filepath.Join(cacheDir, "settings.json"), `{
  "greeterAutoLogin": true,
  "greeterRememberLastUser": true,
  "greeterRememberLastSession": true
}`)
	writeTestFile(t, filepath.Join(cacheDir, ".local/state/memory.json"), `{
  "lastSuccessfulUser": "alice",
  "lastSessionId": "/nix/store/old-session/share/wayland-sessions/example.desktop",
  "lastSessionExec": "/nix/store/old-session/bin/start-example-session"
}`)

	enabled, loginUser, sessionID, err := resolveGreeterAutoLoginState(cacheDir, homeDir)
	if err != nil {
		t.Fatalf("resolveGreeterAutoLoginState returned error: %v", err)
	}
	if !enabled || loginUser != "alice" || sessionID != "example.desktop" {
		t.Fatalf("got enabled=%v user=%q session=%q", enabled, loginUser, sessionID)
	}

	got := upsertInitialSession("", loginUser, cacheDir, true)
	if strings.Contains(got, "/nix/store/old-session") {
		t.Fatalf("initial session must not include stale store path, got:\n%s", got)
	}
}

func TestResolveGreeterAutoLoginStateIgnoresMemoryFlag(t *testing.T) {
	t.Parallel()

	cacheDir := t.TempDir()
	homeDir := t.TempDir()

	writeTestFile(t, filepath.Join(cacheDir, "settings.json"), `{
  "greeterAutoLogin": false,
  "greeterRememberLastUser": true,
  "greeterRememberLastSession": true
}`)
	writeTestFile(t, filepath.Join(cacheDir, ".local/state/memory.json"), `{
  "autoLoginEnabled": true,
  "lastSuccessfulUser": "alice",
  "lastSessionExec": "niri"
}`)

	enabled, loginUser, sessionID, err := resolveGreeterAutoLoginState(cacheDir, homeDir)
	if err != nil {
		t.Fatalf("resolveGreeterAutoLoginState returned error: %v", err)
	}
	if enabled || loginUser != "" || sessionID != "" {
		t.Fatalf("expected disabled with empty user/session, got enabled=%v user=%q session=%q", enabled, loginUser, sessionID)
	}
}

func TestResolveSessionExecInDirs(t *testing.T) {
	t.Parallel()

	oldDir := filepath.Join(t.TempDir(), "wayland-sessions")
	newDir := filepath.Join(t.TempDir(), "wayland-sessions")
	writeTestFile(t, filepath.Join(oldDir, "example.desktop"), `[Desktop Entry]
Name=Example Session
Exec=/nix/store/old-session/bin/start-example-session
`)
	writeTestFile(t, filepath.Join(newDir, "example.desktop"), `[Desktop Entry]
Name=Example Session
Exec=/run/current-system/sw/bin/start-example-session
`)

	got, err := resolveSessionExecInDirs("example.desktop", []string{newDir, oldDir})
	if err != nil {
		t.Fatalf("resolveSessionExecInDirs returned error: %v", err)
	}
	if got != "/run/current-system/sw/bin/start-example-session" {
		t.Fatalf("resolveSessionExecInDirs = %q", got)
	}
}

func TestClearGreeterAutoLoginMemory(t *testing.T) {
	t.Parallel()

	memoryPath := filepath.Join(t.TempDir(), "memory.json")
	writeTestFile(t, memoryPath, `{
  "autoLoginEnabled": true,
  "lastSuccessfulUser": "alice"
}`)

	if err := clearGreeterAutoLoginMemory(memoryPath, ""); err != nil {
		t.Fatalf("clearGreeterAutoLoginMemory returned error: %v", err)
	}

	data, err := os.ReadFile(memoryPath)
	if err != nil {
		t.Fatalf("failed to read memory file: %v", err)
	}
	if strings.Contains(string(data), "autoLoginEnabled") {
		t.Fatalf("expected autoLoginEnabled removed, got: %s", string(data))
	}
	if !strings.Contains(string(data), "lastSuccessfulUser") {
		t.Fatalf("expected other memory fields preserved, got: %s", string(data))
	}
}

func TestNiriGreeterSyncMergesDebugNodesAcrossIncludes(t *testing.T) {
	t.Parallel()

	configDir := t.TempDir()
	configPath := filepath.Join(configDir, "config.kdl")
	writeTestFile(t, configPath, `debug {
    honor-xdg-activation-with-invalid-serial
}

include "dms/debug.kdl"
include "dms/render.kdl"
`)
	writeTestFile(t, filepath.Join(configDir, "dms", "debug.kdl"), `debug {
    honor-xdg-activation-with-invalid-serial
}
`)
	writeTestFile(t, filepath.Join(configDir, "dms", "render.kdl"), `debug {
    render-drm-device "/dev/dri/renderD128"
}
`)

	extractor := newNiriGreeterSync()
	if err := extractor.processFile(configPath); err != nil {
		t.Fatalf("processFile returned error: %v", err)
	}

	rendered := extractor.render()
	if got := strings.Count(rendered, "debug {"); got != 1 {
		t.Fatalf("expected 1 debug node, got %d:\n%s", got, rendered)
	}
	if !strings.Contains(rendered, "honor-xdg-activation-with-invalid-serial") {
		t.Fatalf("expected honor-xdg-activation-with-invalid-serial preserved, got:\n%s", rendered)
	}
	if !strings.Contains(rendered, `render-drm-device "/dev/dri/renderD128"`) {
		t.Fatalf("expected render-drm-device merged, got:\n%s", rendered)
	}
}
