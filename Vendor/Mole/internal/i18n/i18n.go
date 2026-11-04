// Package i18n contains the small, dependency-free localization layer shared
// by Mole's Go terminal interfaces. Machine-readable JSON output deliberately
// does not use these helpers.
package i18n

import (
	"os"
	"strings"
)

// Chinese reports whether MOLE_LANG requests Simplified Chinese. Unset or
// English-prefixed values preserve the upstream English interface.
func Chinese() bool {
	lang := strings.ToLower(strings.TrimSpace(os.Getenv("MOLE_LANG")))
	if lang == "" {
		return false
	}
	return !strings.HasPrefix(lang, "en")
}

// T returns zh when Chinese is active, otherwise en.
func T(en, zh string) string {
	if Chinese() {
		return zh
	}
	return en
}
