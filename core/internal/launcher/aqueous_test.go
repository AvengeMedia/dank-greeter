package launcher

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestAqueousLaunch(t *testing.T) {
	for _, exitCode := range []string{"0", "1"} {
		t.Run("quickshell_exit_"+exitCode, func(t *testing.T) {
			dir := t.TempDir()
			t.Setenv("TMPDIR", dir)
			t.Setenv("PATH", dir)
			binary := filepath.Join(dir, "aqueous")
			const compositor = `#!/bin/sh
[ "$1" = "-no-xwayland" ] && [ "$2" = "-c" ] || exit 2
[ -r "$AQUEOUS_CONFIG" ] || exit 3
[ "$AQUEOUS_LAYOUT" = "$AQUEOUS_CONFIG" ] || exit 4
[ "$AQUEOUS_INPUT" = "$AQUEOUS_CONFIG" ] || exit 5
[ "$AQUEOUS_RULES" = "$AQUEOUS_CONFIG" ] || exit 6
[ "$AQUEOUS_OUTPUTS" = "$AQUEOUS_CONFIG" ] || exit 7
trap 'printf "compositor stopped\n"; exit 0' TERM
/bin/sh -c "$3" &
wait "$!"
exit 8
`
			if err := os.WriteFile(binary, []byte(compositor), 0o700); err != nil {
				t.Fatal(err)
			}
			plan, err := buildPlan("aqueous", "", `printf 'quickshell started\n'; /bin/sh -c 'exit `+exitCode+`'`)
			if err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, binary, plan.argv[1:]...)
			cmd.Env = append(os.Environ(), plan.env...)
			output, err := cmd.CombinedOutput()
			if err != nil {
				t.Fatalf("launch failed: %v\n%s", err, output)
			}
			if got, want := string(output), "quickshell started\ncompositor stopped\n"; got != want {
				t.Fatalf("output = %q, want %q", got, want)
			}
			configPath := strings.TrimPrefix(plan.env[0], "AQUEOUS_CONFIG=")
			config, err := os.ReadFile(configPath)
			if err != nil {
				t.Fatal(err)
			}
			if string(config) != aqueousBaseConfig {
				t.Fatalf("unexpected default config: %s", config)
			}
		})
	}
}

func TestAqueousCustomConfig(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	if err := os.WriteFile(filepath.Join(dir, "aqueous"), []byte("#!/bin/sh\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Chdir(dir)
	const name = "greeter's config.toml"
	const content = "[input]\nxkb_layout = \"de\"\n"
	if err := os.WriteFile(name, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	plan, err := buildPlan("aqueous", name, "qs -p /greeter")
	if err != nil {
		t.Fatal(err)
	}
	if got, want := plan.env[0], "AQUEOUS_CONFIG="+filepath.Join(dir, name); got != want {
		t.Fatalf("config environment = %q, want %q", got, want)
	}
	got, err := os.ReadFile(name)
	if err != nil || string(got) != content {
		t.Fatalf("custom config changed: %q, %v", got, err)
	}
	if _, err := buildPlan("aqueous", "missing.toml", "qs"); !os.IsNotExist(err) {
		t.Fatalf("missing config error = %v", err)
	}
}

func TestAqueousMissingBinary(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	if _, err := buildPlan("aqueous", "", "qs"); err == nil || !strings.Contains(err.Error(), `"aqueous"`) {
		t.Fatalf("missing compositor error = %v", err)
	}
}
