package state

import (
	"fmt"
	"sync"
)

type State int

const (
	Unenrolled State = iota
	Enrolling
	Active
	Reconnecting
	Error
)

func (s State) String() string {
	switch s {
	case Unenrolled:
		return "UNENROLLED"
	case Enrolling:
		return "ENROLLING"
	case Active:
		return "ACTIVE"
	case Reconnecting:
		return "RECONNECTING"
	case Error:
		return "ERROR"
	default:
		return "UNKNOWN"
	}
}

type Machine struct {
	current State
	mu      sync.RWMutex
}

func NewMachine(initial State) *Machine {
	return &Machine{current: initial}
}

func (m *Machine) Set(s State) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.current != s {
		fmt.Printf("[STATE] Transition: %s -> %s\n", m.current, s)
		m.current = s
	}
}

func (m *Machine) Get() State {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.current
}
