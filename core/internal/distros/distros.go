package distros

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"strings"
)

type DistroFamily string

const (
	FamilyArch   DistroFamily = "arch"
	FamilyFedora DistroFamily = "fedora"
	FamilySUSE   DistroFamily = "suse"
	FamilyUbuntu DistroFamily = "ubuntu"
	FamilyDebian DistroFamily = "debian"
	FamilyGentoo DistroFamily = "gentoo"
	FamilyVoid   DistroFamily = "void"
)

type DistroConfig struct {
	ID     string
	Family DistroFamily
}

var Registry = buildRegistry(map[DistroFamily][]string{
	FamilyArch:   {"arch", "archarm", "archcraft", "cachyos", "catos", "endeavouros", "manjaro", "obarun", "garuda", "artix", "XeroLinux"},
	FamilyDebian: {"debian"},
	FamilyFedora: {"fedora", "evernight", "nobara", "fedora-asahi-remix", "bluefin", "ultramarine"},
	FamilyGentoo: {"gentoo"},
	FamilySUSE:   {"opensuse-tumbleweed", "opensuse-leap", "opensuse-slowroll"},
	FamilyUbuntu: {"ubuntu"},
	FamilyVoid:   {"void"},
})

func buildRegistry(families map[DistroFamily][]string) map[string]DistroConfig {
	registry := make(map[string]DistroConfig)
	for family, ids := range families {
		for _, id := range ids {
			registry[id] = DistroConfig{ID: id, Family: family}
		}
	}
	return registry
}

type DistroInfo struct {
	ID string
}

type OSInfo struct {
	Distribution DistroInfo
	Architecture string
}

func GetOSInfo() (*OSInfo, error) {
	if runtime.GOOS != "linux" {
		return nil, fmt.Errorf("only linux is supported, but found %s", runtime.GOOS)
	}
	if runtime.GOARCH != "amd64" && runtime.GOARCH != "arm64" {
		return nil, fmt.Errorf("only amd64 and arm64 are supported, but found %s", runtime.GOARCH)
	}

	info := &OSInfo{Architecture: runtime.GOARCH}

	file, err := os.Open("/etc/os-release")
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		key, value, found := strings.Cut(scanner.Text(), "=")
		if !found || key != "ID" {
			continue
		}
		value = strings.Trim(value, "\"'")
		if _, exists := Registry[value]; !exists {
			return nil, fmt.Errorf("unsupported distribution: %s", value)
		}
		info.Distribution = DistroInfo{ID: value}
	}

	return info, scanner.Err()
}
