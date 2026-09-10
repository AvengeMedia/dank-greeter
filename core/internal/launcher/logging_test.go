package launcher

import (
	"errors"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestJournalStreamHeaderAndPayload(t *testing.T) {
	socketPath := filepath.Join(t.TempDir(), "stdout")
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: socketPath, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	received := make(chan []byte, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			received <- nil
			return
		}
		defer conn.Close()
		data, _ := io.ReadAll(conn)
		received <- data
	}()

	journalStreamPath = socketPath
	defer func() { journalStreamPath = "/run/systemd/journal/stdout" }()

	sink, err := logSink("niri", t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := sink.WriteString("compositor line\n"); err != nil {
		t.Fatal(err)
	}
	sink.Close()

	got := string(<-received)
	want := "dms-greeter/niri\n\n6\n0\n0\n0\n0\ncompositor line\n"
	if got != want {
		t.Fatalf("journal stream = %q, want %q", got, want)
	}
}

func TestLogSinkFallsBackToFileWithoutJournal(t *testing.T) {
	journalStreamPath = filepath.Join(t.TempDir(), "missing")
	defer func() { journalStreamPath = "/run/systemd/journal/stdout" }()

	cacheDir := t.TempDir()
	sink, err := logSink("niri", cacheDir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := sink.WriteString("fallback line\n"); err != nil {
		t.Fatal(err)
	}
	sink.Close()

	got, err := os.ReadFile(filepath.Join(cacheDir, "niri.log"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "fallback line\n" {
		t.Fatalf("log file = %q", got)
	}
}

func TestExecCompositorRedirectsOutputAndKeepsExitCode(t *testing.T) {
	if os.Getenv("DMS_GREETER_EXEC_HELPER") == "1" {
		journalStreamPath = filepath.Join(t.TempDir(), "missing")
		plan := launchPlan{logTag: "fake", argv: []string{"fake-compositor"}}
		if err := execCompositor(plan, os.Getenv("DMS_GREETER_EXEC_CACHE"), false); err != nil {
			t.Fatal(err)
		}
		return
	}

	dir := t.TempDir()
	const compositor = "#!/bin/sh\necho out line\necho err line >&2\nexit 3\n"
	if err := os.WriteFile(filepath.Join(dir, "fake-compositor"), []byte(compositor), 0o700); err != nil {
		t.Fatal(err)
	}
	cacheDir := t.TempDir()

	helper := exec.Command(os.Args[0], "-test.run=^TestExecCompositorRedirectsOutputAndKeepsExitCode$")
	helper.Env = append(os.Environ(), "DMS_GREETER_EXEC_HELPER=1", "DMS_GREETER_EXEC_CACHE="+cacheDir, "PATH="+dir)
	output, err := helper.CombinedOutput()
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) || exitErr.ExitCode() != 3 {
		t.Fatalf("exit = %v, want code 3\n%s", err, output)
	}
	if strings.Contains(string(output), "line") {
		t.Fatalf("compositor output leaked to inherited stdio: %s", output)
	}

	logged, err := os.ReadFile(filepath.Join(cacheDir, "fake.log"))
	if err != nil {
		t.Fatal(err)
	}
	if string(logged) != "out line\nerr line\n" {
		t.Fatalf("log file = %q", logged)
	}
}
