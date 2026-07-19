// Package privesc selects and runs a privilege-escalation tool (sudo, doas,
// or run0) for commands that must modify system configuration.
package privesc

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
)

// Tool identifies a privilege-escalation binary.
type Tool string

const (
	ToolSudo Tool = "sudo"
	ToolDoas Tool = "doas"
	ToolRun0 Tool = "run0"
)

// EnvVar selects a specific tool when set to one of: sudo, doas, run0.
const EnvVar = "DMS_PRIVESC"

var detectionOrder = []Tool{ToolSudo, ToolDoas, ToolRun0}

var (
	detectOnce   sync.Once
	detected     Tool
	detectErr    error
	userSelected bool
)

// Detect returns the tool that should be used for privilege escalation.
// The result is cached after the first call.
func Detect() (Tool, error) {
	detectOnce.Do(func() {
		detected, detectErr = detectTool()
	})
	return detected, detectErr
}

// AvailableTools returns the set of supported tools that are installed on
// PATH, in detection-precedence order.
func AvailableTools() []Tool {
	var out []Tool
	for _, t := range detectionOrder {
		if t.Available() {
			out = append(out, t)
		}
	}
	return out
}

// EnvOverride returns the tool selected by the $DMS_PRIVESC env var (if any)
// along with ok=true when the variable is set.
func EnvOverride() (Tool, bool) {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(EnvVar)))
	if v == "" {
		return "", false
	}
	return Tool(v), true
}

// SetTool forces the detected tool to t, bypassing autodetection. Intended
// for use after the caller has prompted the user for a selection.
func SetTool(t Tool) error {
	if !t.Available() {
		return fmt.Errorf("%q is not installed", t.Name())
	}
	detectOnce = sync.Once{}
	detectOnce.Do(func() {
		detected = t
		detectErr = nil
	})
	userSelected = true
	return nil
}

func detectTool() (Tool, error) {
	switch override := strings.ToLower(strings.TrimSpace(os.Getenv(EnvVar))); override {
	case "":
		// fall through to autodetect
	case string(ToolSudo), string(ToolDoas), string(ToolRun0):
		t := Tool(override)
		if !t.Available() {
			return "", fmt.Errorf("%s=%s but %q is not installed", EnvVar, override, t.Name())
		}
		return t, nil
	default:
		return "", fmt.Errorf("invalid %s=%q: must be one of sudo, doas, run0", EnvVar, override)
	}

	for _, t := range detectionOrder {
		if t.Available() {
			return t, nil
		}
	}
	return "", fmt.Errorf("no supported privilege escalation tool found (tried: sudo, doas, run0)")
}

// Name returns the binary name.
func (t Tool) Name() string { return string(t) }

// Available reports whether this tool's binary is on PATH.
func (t Tool) Available() bool {
	if t == "" {
		return false
	}
	_, err := exec.LookPath(string(t))
	return err == nil
}

// EscapeSingleQuotes escapes single quotes for safe inclusion inside a
// bash single-quoted string.
func EscapeSingleQuotes(s string) string {
	return strings.ReplaceAll(s, "'", "'\\''")
}

// MakeCommand returns a bash command string that runs `command` with the
// detected tool, prompting interactively on a TTY where applicable. The
// sudo-with-password case lives in ExecCommand, which pipes the password via
// stdin so it never lands in argv.
//
// If detection fails, the returned shell string exits 1 with an error
// message so callers that treat the *exec.Cmd as infallible still fail
// deterministically.
func MakeCommand(command string) string {
	t, err := Detect()
	if err != nil {
		return failingShell(err)
	}

	switch t {
	case ToolSudo:
		return fmt.Sprintf("sudo %s", command)
	case ToolDoas:
		return fmt.Sprintf("doas sh -c '%s'", EscapeSingleQuotes(command))
	case ToolRun0:
		return fmt.Sprintf("run0 sh -c '%s'", EscapeSingleQuotes(command))
	default:
		return failingShell(fmt.Errorf("unsupported privilege tool: %q", t))
	}
}

// ExecCommand builds an exec.Cmd that runs `command` as root via the
// detected tool. Detection errors surface at Run() time as a failing
// command writing a clear error to stderr. A sudo password is piped via
// stdin (sudo -S) so it never appears in argv.
func ExecCommand(ctx context.Context, password, command string) *exec.Cmd {
	t, err := Detect()
	if err != nil {
		return exec.CommandContext(ctx, "bash", "-c", failingShell(err))
	}
	if t == ToolSudo && password != "" {
		cmd := exec.CommandContext(ctx, "sudo", "-S", "sh", "-c", command)
		cmd.Stdin = strings.NewReader(password + "\n")
		return cmd
	}
	return exec.CommandContext(ctx, "bash", "-c", MakeCommand(command))
}

// ExecArgv builds an exec.Cmd that runs argv as root via the detected tool.
// No stdin password is supplied; callers relying on non-interactive success
// should ensure cached credentials are present.
func ExecArgv(ctx context.Context, argv ...string) *exec.Cmd {
	if len(argv) == 0 {
		return exec.CommandContext(ctx, "bash", "-c", failingShell(fmt.Errorf("privesc.ExecArgv: argv must not be empty")))
	}
	t, err := Detect()
	if err != nil {
		return exec.CommandContext(ctx, "bash", "-c", failingShell(err))
	}

	switch t {
	case ToolSudo, ToolDoas:
		return exec.CommandContext(ctx, string(t), argv...)
	case ToolRun0:
		return exec.CommandContext(ctx, "run0", argv...)
	default:
		return exec.CommandContext(ctx, "bash", "-c", failingShell(fmt.Errorf("unsupported privilege tool: %q", t)))
	}
}

func failingShell(err error) string {
	return fmt.Sprintf("printf 'privesc: %%s\\n' '%s' >&2; exit 1", EscapeSingleQuotes(err.Error()))
}

// QuoteArgsForShell wraps each argv element in single quotes so the result
// can be safely passed to bash -c.
func QuoteArgsForShell(argv []string) string {
	parts := make([]string, len(argv))
	for i, a := range argv {
		parts[i] = "'" + EscapeSingleQuotes(a) + "'"
	}
	return strings.Join(parts, " ")
}

// Run invokes argv with privilege escalation. When the tool supports stdin
// passwords and password is non-empty, the password is piped in. Otherwise
// argv is invoked directly, which may prompt on a TTY.
// Stdout and Stderr are inherited from the current process.
func Run(ctx context.Context, password string, argv ...string) error {
	if len(argv) == 0 {
		return fmt.Errorf("privesc.Run: argv must not be empty")
	}
	t, err := Detect()
	if err != nil {
		return err
	}

	var cmd *exec.Cmd
	switch {
	case t == ToolSudo && password != "":
		cmd = ExecCommand(ctx, password, QuoteArgsForShell(argv))
	default:
		cmd = ExecArgv(ctx, argv...)
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// stdinIsTTY reports whether stdin is a character device (interactive
// terminal) rather than a pipe or file.
func stdinIsTTY() bool {
	fi, err := os.Stdin.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

// PromptCLI interactively prompts the user to pick a privilege tool when more
// than one is installed and $DMS_PRIVESC is not set. If stdin is not a TTY,
// or only one tool is available, or the env var is set, the detected tool is
// returned without any prompt.
func PromptCLI(out io.Writer, in io.Reader) (Tool, error) {
	if userSelected {
		return Detect()
	}
	if _, envSet := EnvOverride(); envSet {
		return Detect()
	}

	tools := AvailableTools()
	switch len(tools) {
	case 0:
		return "", fmt.Errorf("no supported privilege tool (sudo/doas/run0) found on PATH")
	case 1:
		if err := SetTool(tools[0]); err != nil {
			return "", err
		}
		return tools[0], nil
	}

	if !stdinIsTTY() {
		return Detect()
	}

	fmt.Fprintln(out, "Multiple privilege escalation tools detected:")
	for i, t := range tools {
		fmt.Fprintf(out, "  [%d] %s\n", i+1, t.Name())
	}
	fmt.Fprintf(out, "Choose one [1-%d] (default 1, or set %s=<tool> to skip): ", len(tools), EnvVar)

	reader := bufio.NewReader(in)
	line, err := reader.ReadString('\n')
	if err != nil && err != io.EOF {
		return "", fmt.Errorf("failed to read selection: %w", err)
	}
	line = strings.TrimSpace(line)

	idx := 1
	if line != "" {
		n, convErr := strconv.Atoi(line)
		if convErr != nil || n < 1 || n > len(tools) {
			return "", fmt.Errorf("invalid selection %q", line)
		}
		idx = n
	}

	chosen := tools[idx-1]
	if err := SetTool(chosen); err != nil {
		return "", err
	}
	return chosen, nil
}
