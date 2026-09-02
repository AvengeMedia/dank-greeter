package greeter

import (
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseExecString(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		exec string
		want []string
	}{
		{"plain", "niri --session", []string{"niri", "--session"}},
		{"extra spaces", "niri   --session", []string{"niri", "--session"}},
		{"double quoted arg", `env "with space" run`, []string{"env", "with space", "run"}},
		{"single quoted arg", `env 'with space' run`, []string{"env", "with space", "run"}},
		{"escaped quote in quotes", `sh "say \\"hi\\""`, []string{"sh", `say "hi"`}},
		{"field code dropped", "gnome-session %U", []string{"gnome-session"}},
		{"field code mid-arg", "app --url=%u --run", []string{"app", "--url=", "--run"}},
		{"literal percent", "app 100%% done", []string{"app", "100%", "done"}},
		{"shell metachars stay literal", "sh -c $(reboot); echo", []string{"sh", "-c", "$(reboot);", "echo"}},
		{"empty", "", nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := parseExecString(tt.exec); !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("parseExecString(%q) = %#v, want %#v", tt.exec, got, tt.want)
			}
		})
	}
}

func TestReadSessionDesktopEntryOnlyReadsDesktopEntryGroup(t *testing.T) {
	t.Parallel()

	path := filepath.Join(t.TempDir(), "example.desktop")
	writeTestFile(t, path, `[Desktop Action other]
Exec=/wrong/binary
DesktopNames=Wrong

[Desktop Entry]
Name=Example
Exec = /right/binary --flag
DesktopNames=GNOME;GNOME-Classic
`)

	got, err := readSessionDesktopEntry(path)
	if err != nil {
		t.Fatalf("readSessionDesktopEntry returned error: %v", err)
	}
	want := sessionDesktopEntry{Exec: "/right/binary --flag", DesktopNames: "GNOME;GNOME-Classic"}
	if got != want {
		t.Fatalf("readSessionDesktopEntry = %+v, want %+v", got, want)
	}
}

func TestSessionEnv(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name      string
		sessionID string
		entry     sessionDesktopEntry
		want      []string
	}{
		{
			"gnome",
			"gnome.desktop",
			sessionDesktopEntry{Exec: "gnome-session", DesktopNames: "GNOME"},
			[]string{"XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=gnome", "DESKTOP_SESSION=gnome", "XDG_CURRENT_DESKTOP=GNOME"},
		},
		{
			"multiple desktop names use colon separator",
			"/usr/share/wayland-sessions/plasma.desktop",
			sessionDesktopEntry{Exec: "startplasma-wayland", DesktopNames: "KDE;plasma;"},
			[]string{"XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=plasma", "DESKTOP_SESSION=plasma", "XDG_CURRENT_DESKTOP=KDE:plasma"},
		},
		{
			"no desktop names",
			"niri",
			sessionDesktopEntry{Exec: "niri-session"},
			[]string{"XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=niri", "DESKTOP_SESSION=niri"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := sessionEnv(tt.sessionID, tt.entry); !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("sessionEnv = %#v, want %#v", got, tt.want)
			}
		})
	}
}
