package i18n

import "testing"

func TestT(t *testing.T) {
	t.Setenv("MOLE_LANG", "en_US")
	if got := T("English", "中文"); got != "English" {
		t.Fatalf("English T() = %q", got)
	}

	t.Setenv("MOLE_LANG", "zh_CN")
	if !Chinese() {
		t.Fatal("Chinese() = false for zh_CN")
	}
	if got := T("English", "中文"); got != "中文" {
		t.Fatalf("Chinese T() = %q", got)
	}
}
