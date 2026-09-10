package launcher

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

const vtClearSequence = "\x1b[2J\x1b[H\x1b[3J\x1b[?25l"

const journalPriorityInfo = 6

var journalStreamPath = "/run/systemd/journal/stdout"

func execCompositor(plan launchPlan, cacheDir string, debug bool) error {
	binary, err := exec.LookPath(plan.argv[0])
	if err != nil {
		return err
	}

	cmd := exec.Command(binary, plan.argv[1:]...)
	cmd.Env = append(os.Environ(), plan.env...)
	if debug {
		return syscall.Exec(binary, plan.argv, cmd.Environ())
	}

	clearVT()

	sink, err := logSink(plan.logTag, cacheDir)
	if err != nil {
		return err
	}
	if err := redirectStdio(sink); err != nil {
		return err
	}
	return syscall.Exec(binary, plan.argv, cmd.Environ())
}

// A separate log reader process would leave the compositor writing into a dead
// pipe if it died, so the sink is opened here and inherited across exec.
func logSink(logTag, cacheDir string) (*os.File, error) {
	if journal, err := openJournalStream(journalStreamPath, "dms-greeter/"+logTag); err == nil {
		return journal, nil
	}

	logFile, err := os.OpenFile(filepath.Join(cacheDir, logTag+".log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return nil, fmt.Errorf("opening compositor log file: %w", err)
	}
	return logFile, nil
}

// Speaks the journald stream protocol that sd_journal_stream_fd and
// systemd-cat use: identifier, unit, priority, level prefix, forwarding flags.
func openJournalStream(socketPath, identifier string) (*os.File, error) {
	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: socketPath, Net: "unix"})
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	if err := conn.CloseRead(); err != nil {
		return nil, err
	}
	header := fmt.Sprintf("%s\n\n%d\n0\n0\n0\n0\n", identifier, journalPriorityInfo)
	if _, err := conn.Write([]byte(header)); err != nil {
		return nil, err
	}
	return conn.File()
}

func redirectStdio(sink *os.File) error {
	for _, fd := range []int{int(os.Stdout.Fd()), int(os.Stderr.Fd())} {
		if err := syscall.Dup3(int(sink.Fd()), fd, 0); err != nil {
			return fmt.Errorf("redirecting compositor output: %w", err)
		}
	}
	return nil
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
