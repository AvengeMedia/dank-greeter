package launcher

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
)

const vtClearSequence = "\x1b[2J\x1b[H\x1b[3J\x1b[?25l"

func execCompositor(plan launchPlan, cacheDir string, debug bool) error {
	binary, err := exec.LookPath(plan.argv[0])
	if err != nil {
		return err
	}

	if debug {
		return syscall.Exec(binary, plan.argv, os.Environ())
	}

	clearVT()

	cmd := exec.Command(binary, plan.argv[1:]...)
	sink, cleanup, err := logSink(plan.logTag, cacheDir)
	if err != nil {
		return err
	}
	cmd.Stdout = sink
	cmd.Stderr = sink

	if err := cmd.Start(); err != nil {
		cleanup()
		return err
	}

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)
	defer signal.Stop(signals)
	go func() {
		for sig := range signals {
			cmd.Process.Signal(sig)
		}
	}()

	err = cmd.Wait()
	cleanup()
	if err == nil {
		return nil
	}
	if exitErr, ok := errors.AsType[*exec.ExitError](err); ok {
		os.Exit(exitErr.ExitCode())
	}
	return err
}

// logSink routes compositor output to journald when available, preserving
// diagnostics in a cache-dir log file on systems without it.
func logSink(logTag, cacheDir string) (*os.File, func(), error) {
	if journalBinary, err := exec.LookPath("systemd-cat"); err == nil {
		readEnd, writeEnd, pipeErr := os.Pipe()
		if pipeErr == nil {
			journal := exec.Command(journalBinary, "-t", "dms-greeter/"+logTag, "-p", "info")
			journal.Stdin = readEnd
			if journal.Start() == nil {
				readEnd.Close()
				return writeEnd, func() { writeEnd.Close(); _ = journal.Wait() }, nil
			}
			readEnd.Close()
			writeEnd.Close()
		}
	}

	logFile, err := os.OpenFile(filepath.Join(cacheDir, logTag+".log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return nil, nil, fmt.Errorf("opening compositor log file: %w", err)
	}
	return logFile, func() { logFile.Close() }, nil
}

// clearVT drops retained console text on the controlling VT.
func clearVT() {
	tty, err := os.OpenFile("/dev/tty", os.O_WRONLY, 0)
	if err == nil {
		defer tty.Close()
		if _, err := tty.WriteString(vtClearSequence); err == nil {
			return
		}
	}

	info, err := os.Stdout.Stat()
	if err != nil || info.Mode()&os.ModeCharDevice == 0 {
		return
	}
	fmt.Print(vtClearSequence)
}
