package greeter

import (
	"os"
	"path/filepath"
	"testing"
)

func TestUserGreeterCacheDir(t *testing.T) {
	t.Parallel()

	got := userGreeterCacheDir("/var/cache/dms-greeter", "alice")
	want := filepath.Join("/var/cache/dms-greeter", "users", "alice")
	if got != want {
		t.Fatalf("userGreeterCacheDir() = %q, want %q", got, want)
	}
}

func TestResolveUserProfileImageSource(t *testing.T) {
	t.Parallel()

	homeDir := t.TempDir()
	facePath := filepath.Join(homeDir, ".face")
	writeTestFile(t, facePath, "face")

	got := resolveUserProfileImageSource(homeDir)
	if got != facePath {
		t.Fatalf("resolveUserProfileImageSource() = %q, want %q", got, facePath)
	}
}

func TestIsUserOwnedGreeterCacheSlot(t *testing.T) {
	t.Parallel()

	slot := filepath.Join(GreeterCacheDir, "users", "alice", "settings.json")
	if !isUserOwnedGreeterCacheSlot(slot, "alice") {
		t.Fatalf("expected alice to own %q", slot)
	}
	if isUserOwnedGreeterCacheSlot(slot, "bob") {
		t.Fatalf("expected bob not to own alice slot")
	}
	if isUserOwnedGreeterCacheSlot(filepath.Join(GreeterCacheDir, "settings.json"), "alice") {
		t.Fatalf("expected root cache file not to be a user slot")
	}
}

func TestLocalizeSessionWallpapers(t *testing.T) {
	t.Parallel()

	homeDir := t.TempDir()
	userDir := filepath.Join(homeDir, "users", "alice")
	wallpaperPath := filepath.Join(homeDir, "wall.jpg")
	writeTestFile(t, wallpaperPath, "wallpaper")

	session := map[string]any{
		"wallpaperPath": wallpaperPath,
		"monitorWallpapers": map[string]any{
			"DP-1": wallpaperPath,
		},
	}

	if err := localizeSessionWallpapers(session, userDir, userSlotSyncOpts{}); err != nil {
		t.Fatalf("localizeSessionWallpapers returned error: %v", err)
	}

	gotPath, ok := session["wallpaperPath"].(string)
	if !ok || gotPath == "" {
		t.Fatalf("expected localized wallpaperPath, got %#v", session["wallpaperPath"])
	}
	if gotPath == wallpaperPath {
		t.Fatalf("expected copied wallpaper path, still points to source")
	}

	monitorMap, ok := session["monitorWallpapers"].(map[string]any)
	if !ok {
		t.Fatalf("expected monitorWallpapers map")
	}
	monitorPath, ok := monitorMap["DP-1"].(string)
	if !ok || monitorPath == "" || monitorPath == wallpaperPath {
		t.Fatalf("expected localized monitor wallpaper, got %#v", monitorMap["DP-1"])
	}
}

func TestSessionWallpaperPaths(t *testing.T) {
	t.Parallel()

	session := map[string]any{
		"wallpaperPath":      "/home/alice/Pictures/a.jpg",
		"wallpaperPathLight": "#112233",
		"wallpaperPathDark":  "  ",
		"monitorWallpapers": map[string]any{
			"DP-1": "/home/alice/Pictures/b.jpg",
			"DP-2": "#445566",
		},
		"monitorWallpapersDark": "not-a-map",
	}

	got := sessionWallpaperPaths(session)
	want := []string{"/home/alice/Pictures/a.jpg", "/home/alice/Pictures/b.jpg"}
	if len(got) != len(want) {
		t.Fatalf("sessionWallpaperPaths() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("sessionWallpaperPaths()[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestExpandHomePath(t *testing.T) {
	t.Parallel()

	cases := map[string]string{
		"~":                  "/home/alice",
		"~/Pictures/a.jpg":   "/home/alice/Pictures/a.jpg",
		"/mnt/walls/a.jpg":   "/mnt/walls/a.jpg",
		"Pictures/a.jpg":     "/home/alice/Pictures/a.jpg",
		"~user/Pictures.jpg": "/home/alice/~user/Pictures.jpg",
	}
	for input, want := range cases {
		if got := expandHomePath("/home/alice", input); got != want {
			t.Fatalf("expandHomePath(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestWallpaperAccessDirs(t *testing.T) {
	t.Parallel()

	homeDir := "/home/alice"
	paths := []string{
		filepath.Join(homeDir, "Pictures", "Walls", "a.jpg"),
		filepath.Join(homeDir, ".local", "share", "wallpapers", "b.jpg"),
		"~/Pictures/Walls/c.jpg",
		"/mnt/data/walls/d.jpg",
		filepath.Join(homeDir, ".config", "DankMaterialShell", "e.jpg"),
	}

	got := wallpaperAccessDirs(homeDir, paths)
	want := []string{
		"/home",
		"/home/alice/.config/DankMaterialShell",
		"/home/alice/.local/share/wallpapers",
		"/home/alice/Pictures",
		"/home/alice/Pictures/Walls",
		"/mnt",
		"/mnt/data",
		"/mnt/data/walls",
	}
	if len(got) != len(want) {
		t.Fatalf("wallpaperAccessDirs() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("wallpaperAccessDirs()[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestIsUserSlotSnapshotArtifact(t *testing.T) {
	t.Parallel()

	for _, name := range []string{"wallpaper.jpg", "wallpaper-monitor-DP-1.png", "wallpaper-light.webp", "profile.png", "custom-theme.json"} {
		if !isUserSlotSnapshotArtifact(name) {
			t.Fatalf("expected %q to be a snapshot artifact", name)
		}
	}
	for _, name := range []string{"settings.json", "session.json", "colors.json", "greeter_wallpaper_override.jpg"} {
		if isUserSlotSnapshotArtifact(name) {
			t.Fatalf("expected %q to be kept", name)
		}
	}
}

func TestLinkUserSlotReplacesSnapshot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	homeDir := filepath.Join(root, "home")
	sources := userSlotSources{
		settings: filepath.Join(homeDir, ".config", "DankMaterialShell", "settings.json"),
		session:  filepath.Join(homeDir, ".local", "state", "DankMaterialShell", "session.json"),
		colors:   filepath.Join(homeDir, ".cache", "DankMaterialShell", "dms-colors.json"),
	}
	writeTestFile(t, sources.settings, `{"currentThemeName":"blue"}`)
	writeTestFile(t, sources.session, `{"wallpaperPath":"/x.jpg"}`)

	userDir := filepath.Join(root, "users", "alice")
	writeTestFile(t, filepath.Join(userDir, "settings.json"), `{"customThemeFile":"old"}`)
	writeTestFile(t, filepath.Join(userDir, "session.json"), `{}`)
	writeTestFile(t, filepath.Join(userDir, "colors.json"), `{}`)
	writeTestFile(t, filepath.Join(userDir, "wallpaper.jpg"), "old")
	writeTestFile(t, filepath.Join(userDir, "wallpaper-monitor-DP-1.jpg"), "old")
	writeTestFile(t, filepath.Join(userDir, "profile.png"), "old")
	writeTestFile(t, filepath.Join(userDir, "custom-theme.json"), "old")
	writeTestFile(t, filepath.Join(userDir, "greeter_wallpaper_override.jpg"), "keep")

	opts := userSlotSyncOpts{profileOnly: true, username: "alice", directWrite: func(string) bool { return true }}
	if err := linkUserSlot(userDir, sources, opts); err != nil {
		t.Fatalf("linkUserSlot returned error: %v", err)
	}

	for name, source := range map[string]string{"settings.json": sources.settings, "session.json": sources.session, "colors.json": sources.colors} {
		target, err := os.Readlink(filepath.Join(userDir, name))
		if err != nil {
			t.Fatalf("expected %s to be a symlink: %v", name, err)
		}
		if target != source {
			t.Fatalf("%s links to %q, want %q", name, target, source)
		}
	}
	for _, name := range []string{"wallpaper.jpg", "wallpaper-monitor-DP-1.jpg", "profile.png", "custom-theme.json"} {
		if _, err := os.Lstat(filepath.Join(userDir, name)); !os.IsNotExist(err) {
			t.Fatalf("expected stale %s to be removed", name)
		}
	}
	if _, err := os.Stat(filepath.Join(userDir, "greeter_wallpaper_override.jpg")); err != nil {
		t.Fatalf("expected override copy to be kept: %v", err)
	}
	if data, _ := os.ReadFile(sources.settings); string(data) != `{"currentThemeName":"blue"}` {
		t.Fatalf("source settings were modified: %s", data)
	}
}

func TestSnapshotWriteDoesNotFollowLinkedSlot(t *testing.T) {
	t.Parallel()

	root := t.TempDir()
	source := filepath.Join(root, "home", "session.json")
	writeTestFile(t, source, `{"live":true}`)
	dest := filepath.Join(root, "users", "alice", "session.json")
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(source, dest); err != nil {
		t.Fatal(err)
	}

	opts := userSlotSyncOpts{profileOnly: true, username: "alice", directWrite: func(string) bool { return true }}
	if err := writeFileWithPrivesc(dest, []byte(`{"snapshot":true}`), opts); err != nil {
		t.Fatalf("writeFileWithPrivesc returned error: %v", err)
	}

	if data, _ := os.ReadFile(source); string(data) != `{"live":true}` {
		t.Fatalf("live source was overwritten through the symlink: %s", data)
	}
	info, err := os.Lstat(dest)
	if err != nil || info.Mode()&os.ModeSymlink != 0 {
		t.Fatalf("expected %s to be a regular file after snapshot write", dest)
	}
}

func TestInspectUserSlot(t *testing.T) {
	t.Parallel()

	cacheDir := t.TempDir()
	liveSource := filepath.Join(cacheDir, "home", "session.json")
	writeTestFile(t, liveSource, "{}")

	userDir := func(name string) string { return filepath.Join(cacheDir, "users", name) }
	if err := os.MkdirAll(userDir("live"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(liveSource, filepath.Join(userDir("live"), "session.json")); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(userDir("broken"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(cacheDir, "missing.json"), filepath.Join(userDir("broken"), "session.json")); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, filepath.Join(userDir("snapshot"), "session.json"), "{}")
	writeTestFile(t, filepath.Join(userDir("empty"), "settings.json"), "{}")

	cases := map[string]UserSlotState{
		"live":     UserSlotLive,
		"broken":   UserSlotBroken,
		"snapshot": UserSlotSnapshot,
		"empty":    UserSlotMissing,
		"nobody":   UserSlotMissing,
	}
	for name, want := range cases {
		if got := InspectUserSlot(cacheDir, name); got != want {
			t.Fatalf("InspectUserSlot(%q) = %v, want %v", name, got, want)
		}
	}

	slots, err := ListUserSlots(cacheDir)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"broken", "empty", "live", "snapshot"}
	if len(slots) != len(want) {
		t.Fatalf("ListUserSlots() = %v, want %v", slots, want)
	}
	for i := range want {
		if slots[i] != want[i] {
			t.Fatalf("ListUserSlots()[%d] = %q, want %q", i, slots[i], want[i])
		}
	}
}
