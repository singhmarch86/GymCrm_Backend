package auth

import (
	"testing"

	"gymcrm/configs"
)

// stubPolicy stands in for Config so the gate can be tested on its own.
type stubPolicy struct {
	mode configs.RegistrationMode
	code string
}

func (s stubPolicy) Registration() configs.RegistrationMode { return s.mode }
func (s stubPolicy) RegistrationInviteCode() string         { return s.code }

func gate(mode configs.RegistrationMode, code string) *Handler {
	return &Handler{registration: stubPolicy{mode: mode, code: code}}
}

func TestOpenRegistrationAllowsAnyone(t *testing.T) {
	h := gate(configs.RegistrationOpen, "")
	if !h.registrationAllowed("") {
		t.Fatal("open registration rejected an empty code")
	}
	if !h.registrationAllowed("anything") {
		t.Fatal("open registration rejected a supplied code")
	}
}

func TestClosedRegistrationRefusesEverything(t *testing.T) {
	h := gate(configs.RegistrationClosed, "")
	if h.registrationAllowed("") {
		t.Fatal("closed registration accepted an empty code")
	}
	// Notably including a code that would be valid in invite mode — closed
	// means closed, not "closed unless you guess something".
	if h.registrationAllowed("hunter2") {
		t.Fatal("closed registration accepted a code")
	}
}

func TestInviteModeRequiresTheExactCode(t *testing.T) {
	h := gate(configs.RegistrationInvite, "correct-horse-battery")

	if !h.registrationAllowed("correct-horse-battery") {
		t.Fatal("the correct invite code was rejected")
	}
	for _, wrong := range []string{"", "correct-horse", "correct-horse-batteryy", "CORRECT-HORSE-BATTERY"} {
		if h.registrationAllowed(wrong) {
			t.Fatalf("invite mode accepted %q", wrong)
		}
	}
}

func TestInviteModeWithNoCodeConfiguredFailsClosed(t *testing.T) {
	// Misconfiguration must not become an open door. Without this, invite mode
	// with an unset code would let every caller in with an empty string, which
	// is worse than having no gate at all because it looks protected.
	h := gate(configs.RegistrationInvite, "")
	if h.registrationAllowed("") {
		t.Fatal("invite mode with no configured code accepted an empty code")
	}
	if h.registrationAllowed("anything") {
		t.Fatal("invite mode with no configured code accepted a code")
	}
}

func TestUnknownModeFailsClosed(t *testing.T) {
	// If a future mode is added and this switch is not updated, the safe
	// outcome is refusal rather than silently opening registration.
	h := gate(configs.RegistrationMode(99), "x")
	if h.registrationAllowed("x") {
		t.Fatal("an unrecognised registration mode defaulted to open")
	}
}
