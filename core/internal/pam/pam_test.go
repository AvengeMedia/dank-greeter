package pam

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTestFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("failed to create parent dir for %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("failed to write %s: %v", path, err)
	}
}

type pamTestEnv struct {
	pamDir               string
	greetdPath           string
	tmpDir               string
	homeDir              string
	availableModules     map[string]bool
	fingerprintAvailable bool
}

func newPamTestEnv(t *testing.T) *pamTestEnv {
	t.Helper()

	root := t.TempDir()
	pamDir := filepath.Join(root, "pam.d")
	tmpDir := filepath.Join(root, "tmp")
	homeDir := filepath.Join(root, "home")

	for _, dir := range []string{pamDir, tmpDir, homeDir} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("failed to create %s: %v", dir, err)
		}
	}

	return &pamTestEnv{
		pamDir:           pamDir,
		greetdPath:       filepath.Join(pamDir, "greetd"),
		tmpDir:           tmpDir,
		homeDir:          homeDir,
		availableModules: map[string]bool{},
	}
}

func (e *pamTestEnv) writePamFile(t *testing.T, name string, content string) {
	t.Helper()
	writeTestFile(t, filepath.Join(e.pamDir, name), content)
}

func (e *pamTestEnv) writeSettings(t *testing.T, content string) {
	t.Helper()
	writeTestFile(t, filepath.Join(e.homeDir, ".config", "DankMaterialShell", "settings.json"), content)
}

func (e *pamTestEnv) deps(isNixOS bool) syncDeps {
	return syncDeps{
		pamDir:     e.pamDir,
		greetdPath: e.greetdPath,
		isNixOS:    func() bool { return isNixOS },
		readFile:   os.ReadFile,
		stat:       os.Stat,
		createTemp: func(_ string, pattern string) (*os.File, error) {
			return os.CreateTemp(e.tmpDir, pattern)
		},
		removeFile: os.Remove,
		runSudoCmd: func(_ string, command string, args ...string) error {
			switch command {
			case "cp":
				if len(args) != 2 {
					return fmt.Errorf("unexpected cp args: %v", args)
				}
				data, err := os.ReadFile(args[0])
				if err != nil {
					return err
				}
				if err := os.MkdirAll(filepath.Dir(args[1]), 0o755); err != nil {
					return err
				}
				return os.WriteFile(args[1], data, 0o644)
			case "chmod":
				if len(args) != 2 {
					return fmt.Errorf("unexpected chmod args: %v", args)
				}
				return nil
			case "rm":
				if len(args) != 2 || args[0] != "-f" {
					return fmt.Errorf("unexpected rm args: %v", args)
				}
				if err := os.Remove(args[1]); err != nil && !os.IsNotExist(err) {
					return err
				}
				return nil
			default:
				return fmt.Errorf("unexpected sudo command: %s %v", command, args)
			}
		},
		pamModuleExists: func(module string) bool {
			return e.availableModules[module]
		},
		fingerprintAvailableForCurrentUser: func() bool {
			return e.fingerprintAvailable
		},
	}
}

func readFileString(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("failed to read %s: %v", path, err)
	}
	return string(data)
}

func TestSyncGreeterPamConfigWithDeps(t *testing.T) {
	t.Parallel()

	t.Run("adds managed block for enabled auth modules", func(t *testing.T) {
		t.Parallel()

		env := newPamTestEnv(t)
		env.availableModules["pam_fprintd.so"] = true
		env.availableModules["pam_u2f.so"] = true
		env.writePamFile(t, "greetd", "#%PAM-1.0\nauth include system-auth\naccount include system-auth\n")
		env.writePamFile(t, "system-auth", "auth sufficient pam_unix.so\naccount required pam_unix.so\n")

		settings := AuthSettings{GreeterEnableFprint: true, GreeterEnableU2f: true}
		if err := syncGreeterPamConfigWithDeps(func(string) {}, "", settings, false, env.deps(false)); err != nil {
			t.Fatalf("syncGreeterPamConfigWithDeps returned error: %v", err)
		}

		got := readFileString(t, env.greetdPath)
		for _, want := range []string{
			GreeterPamManagedBlockStart,
			"auth sufficient pam_fprintd.so max-tries=2 timeout=10",
			"auth sufficient pam_u2f.so cue nouserok timeout=10",
			GreeterPamManagedBlockEnd,
		} {
			if !strings.Contains(got, want) {
				t.Errorf("missing expected string %q in greetd PAM:\n%s", want, got)
			}
		}
		if strings.Index(got, GreeterPamManagedBlockStart) > strings.Index(got, "auth include system-auth") {
			t.Fatalf("managed block was not inserted before first auth line:\n%s", got)
		}
	})

	t.Run("avoids duplicate fingerprint when included stack already provides it", func(t *testing.T) {
		t.Parallel()

		env := newPamTestEnv(t)
		env.availableModules["pam_fprintd.so"] = true
		env.fingerprintAvailable = true
		original := "#%PAM-1.0\nauth include system-auth\naccount include system-auth\n"
		env.writePamFile(t, "greetd", original)
		env.writePamFile(t, "system-auth", "auth sufficient pam_fprintd.so max-tries=1\nauth sufficient pam_unix.so\n")

		settings := AuthSettings{GreeterEnableFprint: true}
		if err := syncGreeterPamConfigWithDeps(func(string) {}, "", settings, false, env.deps(false)); err != nil {
			t.Fatalf("syncGreeterPamConfigWithDeps returned error: %v", err)
		}

		got := readFileString(t, env.greetdPath)
		if got != original {
			t.Fatalf("greetd PAM changed despite included pam_fprintd stack\ngot:\n%s\nwant:\n%s", got, original)
		}
		if strings.Contains(got, GreeterPamManagedBlockStart) {
			t.Fatalf("managed block should not be inserted when included stack already has pam_fprintd:\n%s", got)
		}
	})
}

func TestRemoveManagedGreeterPamBlockWithDeps(t *testing.T) {
	t.Parallel()

	env := newPamTestEnv(t)
	env.writePamFile(t, "greetd", "#%PAM-1.0\n"+
		legacyGreeterPamFprintComment+"\n"+
		"auth sufficient pam_fprintd.so max-tries=1\n"+
		GreeterPamManagedBlockStart+"\n"+
		"auth sufficient pam_u2f.so cue nouserok timeout=10\n"+
		GreeterPamManagedBlockEnd+"\n"+
		"auth include system-auth\n")

	if err := removeManagedGreeterPamBlockWithDeps(func(string) {}, "", env.deps(false)); err != nil {
		t.Fatalf("removeManagedGreeterPamBlockWithDeps returned error: %v", err)
	}

	got := readFileString(t, env.greetdPath)
	if strings.Contains(got, GreeterPamManagedBlockStart) || strings.Contains(got, legacyGreeterPamFprintComment) {
		t.Fatalf("managed or legacy DMS auth lines remained in greetd PAM:\n%s", got)
	}
	if !strings.Contains(got, "auth include system-auth") {
		t.Fatalf("expected non-DMS greetd auth lines to remain:\n%s", got)
	}
}

func containsSubstr(items []string, substr string) bool {
	for _, item := range items {
		if strings.Contains(item, substr) {
			return true
		}
	}
	return false
}

func TestSyncAuthConfigWithDeps(t *testing.T) {
	t.Parallel()

	t.Run("skips greetd sync when greeter PAM service is not installed", func(t *testing.T) {
		t.Parallel()

		env := newPamTestEnv(t)
		env.writeSettings(t, `{"greeterEnableFprint":true}`)

		var logs []string
		err := syncAuthConfigWithDeps(func(msg string) {
			logs = append(logs, msg)
		}, "", SyncAuthOptions{HomeDir: env.homeDir}, env.deps(false))
		if err != nil {
			t.Fatalf("syncAuthConfigWithDeps returned error: %v", err)
		}

		if len(logs) == 0 || !strings.Contains(logs[len(logs)-1], "greetd not found") {
			t.Fatalf("expected greetd skip log, got %v", logs)
		}
	})

	t.Run("greeter toggles are respected", func(t *testing.T) {
		t.Parallel()

		env := newPamTestEnv(t)
		env.availableModules["pam_fprintd.so"] = true
		env.writeSettings(t, `{"greeterEnableFprint":true,"greeterEnableU2f":false}`)
		env.writePamFile(t, "system-auth", "auth sufficient pam_unix.so try_first_pass nullok\naccount required pam_access.so\n")
		env.writePamFile(t, "greetd", "#%PAM-1.0\nauth include system-auth\naccount include system-auth\n")

		err := syncAuthConfigWithDeps(func(string) {}, "", SyncAuthOptions{HomeDir: env.homeDir}, env.deps(false))
		if err != nil {
			t.Fatalf("syncAuthConfigWithDeps returned error: %v", err)
		}

		greetd := readFileString(t, env.greetdPath)
		if !strings.Contains(greetd, "auth sufficient pam_fprintd.so max-tries=2 timeout=10") {
			t.Fatalf("expected greetd PAM to receive fingerprint auth block:\n%s", greetd)
		}
		if strings.Contains(greetd, "auth sufficient pam_u2f.so cue nouserok timeout=10") {
			t.Fatalf("did not expect greetd PAM to receive U2F auth block:\n%s", greetd)
		}
	})

	t.Run("externally managed greetd is stripped and greeter sync skipped", func(t *testing.T) {
		t.Parallel()

		env := newPamTestEnv(t)
		env.availableModules["pam_fprintd.so"] = true
		env.writeSettings(t, `{"greeterPamExternallyManaged":true,"greeterEnableFprint":true}`)
		env.writePamFile(t, "system-auth", "auth sufficient pam_unix.so\naccount required pam_unix.so\n")
		env.writePamFile(t, "greetd", "#%PAM-1.0\nauth include system-auth\n"+
			GreeterPamManagedBlockStart+"\n"+
			"auth sufficient pam_fprintd.so max-tries=2 timeout=10\n"+
			GreeterPamManagedBlockEnd+"\n")

		var logs []string
		err := syncAuthConfigWithDeps(func(msg string) {
			logs = append(logs, msg)
		}, "", SyncAuthOptions{HomeDir: env.homeDir}, env.deps(false))
		if err != nil {
			t.Fatalf("syncAuthConfigWithDeps returned error: %v", err)
		}

		greetd := readFileString(t, env.greetdPath)
		if strings.Contains(greetd, GreeterPamManagedBlockStart) || strings.Contains(greetd, "pam_fprintd") {
			t.Fatalf("expected DMS-managed block stripped from externally managed greetd:\n%s", greetd)
		}
		if !strings.Contains(greetd, "auth include system-auth") {
			t.Fatalf("expected non-DMS greetd lines to remain:\n%s", greetd)
		}
		if !containsSubstr(logs, "externally managed") {
			t.Fatalf("expected externally-managed skip log, got %v", logs)
		}
	})

	t.Run("NixOS remains informational and non-mutating", func(t *testing.T) {
		t.Parallel()

		env := newPamTestEnv(t)
		env.availableModules["pam_fprintd.so"] = true
		env.availableModules["pam_u2f.so"] = true
		env.writeSettings(t, `{"greeterEnableFprint":true,"greeterEnableU2f":true}`)
		originalGreetd := "#%PAM-1.0\nauth include system-auth\naccount include system-auth\n"
		env.writePamFile(t, "greetd", originalGreetd)

		var logs []string
		err := syncAuthConfigWithDeps(func(msg string) {
			logs = append(logs, msg)
		}, "", SyncAuthOptions{HomeDir: env.homeDir}, env.deps(true))
		if err != nil {
			t.Fatalf("syncAuthConfigWithDeps returned error: %v", err)
		}

		if got := readFileString(t, env.greetdPath); got != originalGreetd {
			t.Fatalf("expected greetd PAM to remain unchanged on NixOS path\ngot:\n%s\nwant:\n%s", got, originalGreetd)
		}
		if !containsSubstr(logs, "NixOS detected") {
			t.Fatalf("expected informational NixOS logs, got %v", logs)
		}
	})
}
