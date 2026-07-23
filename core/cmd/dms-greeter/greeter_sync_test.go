package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func writeLocalGreeterTestFile(t *testing.T, path string, mode os.FileMode) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("create test directory: %v", err)
	}
	if err := os.WriteFile(path, []byte("test"), mode); err != nil {
		t.Fatalf("write test file: %v", err)
	}
}

func makeLocalGreeterTestCheckout(t *testing.T) localGreeterCheckout {
	t.Helper()
	root := t.TempDir()
	writeLocalGreeterTestFile(t, filepath.Join(root, "core", "go.mod"), 0o644)
	writeLocalGreeterTestFile(t, filepath.Join(root, "core", "Makefile"), 0o644)
	writeLocalGreeterTestFile(t, filepath.Join(root, "quickshell", "shell.qml"), 0o644)
	writeLocalGreeterTestFile(t, filepath.Join(root, "quickshell", "DankCommon", "Widgets", "DankIcon.qml"), 0o644)
	return localGreeterCheckout{rootDir: root, shellDir: filepath.Join(root, "quickshell")}
}

func TestResolveLocalCheckoutCandidateRequiresGoAndQML(t *testing.T) {
	checkout := makeLocalGreeterTestCheckout(t)

	for _, candidate := range []string{checkout.rootDir, checkout.shellDir, filepath.Join(checkout.rootDir, "core")} {
		got, ok := resolveLocalCheckoutCandidate(candidate)
		if !ok {
			t.Fatalf("expected %s to resolve", candidate)
		}
		if got != checkout {
			t.Fatalf("resolveLocalCheckoutCandidate(%q) = %+v, want %+v", candidate, got, checkout)
		}
	}

	qmlOnly := t.TempDir()
	writeLocalGreeterTestFile(t, filepath.Join(qmlOnly, "shell.qml"), 0o644)
	if _, ok := resolveLocalCheckoutCandidate(qmlOnly); ok {
		t.Fatal("QML-only directory must not resolve now that --local builds Go")
	}
}

func TestBuildAndInstallLocalGreeterBuildsEmbeddedBinary(t *testing.T) {
	checkout := makeLocalGreeterTestCheckout(t)
	var buildCall []string
	var installedSource string

	deps := localGreeterBuildDeps{
		commandExists: func(string) bool { return true },
		runBuild: func(dir, command string, args ...string) error {
			buildCall = append([]string{dir, command}, args...)
			writeLocalGreeterTestFile(t, filepath.Join(dir, "bin", "dms-greeter-local"), 0o755)
			return nil
		},
		install: func(source string, _ func(string), _ string) (string, error) {
			installedSource = source
			return "/usr/local/bin/dms-greeter-local", nil
		},
	}

	got, err := buildAndInstallLocalGreeter(checkout, func(string) {}, "", deps)
	if err != nil {
		t.Fatalf("buildAndInstallLocalGreeter returned error: %v", err)
	}
	wantBuild := []string{filepath.Join(checkout.rootDir, "core"), "make", "build", "BINARY_NAME=dms-greeter-local"}
	if !reflect.DeepEqual(buildCall, wantBuild) {
		t.Fatalf("build call = %v, want %v", buildCall, wantBuild)
	}
	if installedSource != filepath.Join(checkout.rootDir, "core", "bin", "dms-greeter-local") {
		t.Fatalf("installed source = %q", installedSource)
	}
	if got != "/usr/local/bin/dms-greeter-local" {
		t.Fatalf("installed path = %q", got)
	}
}

func TestBuildAndInstallLocalGreeterRequiresQMLSubmodule(t *testing.T) {
	checkout := makeLocalGreeterTestCheckout(t)
	if err := os.Remove(filepath.Join(checkout.shellDir, "DankCommon", "Widgets", "DankIcon.qml")); err != nil {
		t.Fatal(err)
	}

	_, err := buildAndInstallLocalGreeter(checkout, func(string) {}, "", localGreeterBuildDeps{
		commandExists: func(string) bool { return true },
		runBuild:      func(string, string, ...string) error { return errors.New("must not run") },
		install:       func(string, func(string), string) (string, error) { return "", errors.New("must not run") },
	})
	if err == nil || !strings.Contains(err.Error(), "git submodule update --init dank-qml-common") {
		t.Fatalf("expected submodule guidance, got %v", err)
	}
}
