package launcher

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

var niriOverrideFiles = []string{
	"/usr/share/greetd/niri_overrides.kdl",
	"/etc/greetd/niri_overrides.kdl",
}

const niriBaseConfig = `hotkey-overlay {
    skip-at-startup
}

environment {
    DMS_RUN_GREETER "1"
}

gestures {
   hot-corners {
     off
   }
}

layout {
  background-color "#000000"
}
`

var hyprlandLuaPattern = regexp.MustCompile(`(^|[^[:alnum:]_])hl\.`)

type launchPlan struct {
	logTag string
	argv   []string
}

func buildPlan(compositor, configPath, qsCmd string) (launchPlan, error) {
	switch compositor {
	case "niri":
		return buildNiriPlan(configPath, qsCmd)
	case "hyprland":
		return buildHyprlandPlan(configPath, qsCmd)
	case "sway":
		return buildAppendExecPlan("sway", configPath, fmt.Sprintf("\nexec \"%s; swaymsg exit\"\n", qsCmd), "sway", "--unsupported-gpu", "-c")
	case "scroll":
		return buildAppendExecPlan("scroll", configPath, fmt.Sprintf("\nexec \"%s; scrollmsg exit\"\n", qsCmd), "scroll", "-c")
	case "miracle", "miracle-wm":
		return buildAppendExecPlan("miracle", configPath, fmt.Sprintf("\nexec \"%s; miraclemsg exit\"\n", qsCmd), "miracle-wm", "-c")
	case "labwc":
		return buildLabwcPlan(configPath, qsCmd)
	case "mango", "mangowc":
		return buildMangoPlan(configPath, qsCmd)
	default:
		return launchPlan{}, fmt.Errorf("unsupported compositor: %s\nSupported compositors: niri, hyprland, sway, scroll, miracle, mango, labwc", compositor)
	}
}

func buildNiriPlan(configPath, qsCmd string) (launchPlan, error) {
	if err := requireCommand("niri"); err != nil {
		return launchPlan{}, err
	}

	base := niriBaseConfig
	if configPath != "" {
		content, err := os.ReadFile(configPath)
		if err != nil {
			return launchPlan{}, err
		}
		base = string(content)
	}

	var builder strings.Builder
	builder.WriteString(base)
	for _, overrideFile := range niriOverrideFiles {
		if _, err := os.Stat(overrideFile); err != nil {
			continue
		}
		fmt.Fprintf(&builder, "\ninclude %q\n", overrideFile)
	}
	fmt.Fprintf(&builder, "\nspawn-at-startup \"sh\" \"-c\" \"%s; niri msg action quit --skip-confirmation\"\n", qsCmd)

	tempConfig, err := writeTempConfig(builder.String(), "")
	if err != nil {
		return launchPlan{}, err
	}
	return launchPlan{logTag: "niri", argv: []string{"niri", "-c", tempConfig}}, nil
}

func buildHyprlandPlan(configPath, qsCmd string) (launchPlan, error) {
	startHyprland := commandExists("start-hyprland")
	if !startHyprland && !commandExists("Hyprland") {
		return launchPlan{}, fmt.Errorf("neither 'start-hyprland' nor 'Hyprland' was found in PATH")
	}

	var tempConfig string
	var err error
	switch {
	case configPath != "" && isHyprlandLuaConfig(configPath):
		content, readErr := os.ReadFile(configPath)
		if readErr != nil {
			return launchPlan{}, readErr
		}
		lua := fmt.Sprintf("%s\nhl.on(\"hyprland.start\", function()\n    hl.exec_cmd('sh -c \"%s; hyprctl dispatch exit\"')\nend)\n", content, qsCmd)
		tempConfig, err = writeTempConfig(lua, ".lua")
	case configPath == "":
		conf := fmt.Sprintf("env = DMS_RUN_GREETER,1\n\nmisc {\n    disable_hyprland_logo = true\n}\n\nexec-once = sh -c \"%s; hyprctl dispatch exit\"\n", qsCmd)
		tempConfig, err = writeTempConfig(conf, "")
	default:
		content, readErr := os.ReadFile(configPath)
		if readErr != nil {
			return launchPlan{}, readErr
		}
		conf := fmt.Sprintf("%s\nexec-once = sh -c \"%s; hyprctl dispatch exit\"\n", content, qsCmd)
		tempConfig, err = writeTempConfig(conf, "")
	}
	if err != nil {
		return launchPlan{}, err
	}

	if startHyprland {
		return launchPlan{logTag: "hyprland", argv: []string{"start-hyprland", "--", "--config", tempConfig}}, nil
	}
	return launchPlan{logTag: "hyprland", argv: []string{"Hyprland", "-c", tempConfig}}, nil
}

func buildAppendExecPlan(logTag, configPath, execLine, binary string, argvPrefix ...string) (launchPlan, error) {
	if err := requireCommand(binary); err != nil {
		return launchPlan{}, err
	}

	base := ""
	if configPath != "" {
		content, err := os.ReadFile(configPath)
		if err != nil {
			return launchPlan{}, err
		}
		base = string(content)
	}

	tempConfig, err := writeTempConfig(base+execLine, "")
	if err != nil {
		return launchPlan{}, err
	}
	return launchPlan{logTag: logTag, argv: append(append([]string{binary}, argvPrefix...), tempConfig)}, nil
}

func buildLabwcPlan(configPath, qsCmd string) (launchPlan, error) {
	if err := requireCommand("labwc"); err != nil {
		return launchPlan{}, err
	}
	if configPath != "" {
		return launchPlan{logTag: "labwc", argv: []string{"labwc", "--config", configPath, "--session", qsCmd}}, nil
	}
	return launchPlan{logTag: "labwc", argv: []string{"labwc", "--session", qsCmd}}, nil
}

func buildMangoPlan(configPath, qsCmd string) (launchPlan, error) {
	if err := requireCommand("mango"); err != nil {
		return launchPlan{}, err
	}
	session := fmt.Sprintf("%s && mmsg dispatch quit", qsCmd)
	if configPath != "" {
		return launchPlan{logTag: "mango", argv: []string{"mango", "-c", configPath, "-s", session}}, nil
	}
	return launchPlan{logTag: "mango", argv: []string{"mango", "-s", session}}, nil
}

func isHyprlandLuaConfig(configPath string) bool {
	if strings.HasSuffix(configPath, ".lua") {
		return true
	}
	content, err := os.ReadFile(configPath)
	if err != nil {
		return false
	}
	return hyprlandLuaPattern.Match(content)
}

func writeTempConfig(content, suffix string) (string, error) {
	file, err := os.CreateTemp("", "dms-greeter-*"+suffix)
	if err != nil {
		return "", err
	}
	defer file.Close()
	if _, err := file.WriteString(content); err != nil {
		os.Remove(file.Name())
		return "", err
	}
	return file.Name(), nil
}

func requireCommand(name string) error {
	if commandExists(name) {
		return nil
	}
	return fmt.Errorf("required command %q was not found in PATH", name)
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}
