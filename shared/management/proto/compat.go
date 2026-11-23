package proto

// NetbirdConfig is the historical name of AuroraNetConfig. Modules that still
// import github.com/netbirdio/netbird (management-integrations, for example)
// reference it, so the alias keeps those dependencies compiling.
type NetbirdConfig = AuroraNetConfig
