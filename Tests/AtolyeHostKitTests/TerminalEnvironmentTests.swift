import Testing
@testable import AtolyeHostKit

@Suite struct TerminalEnvironmentTests {
    @Test func stripsClaudeCodeAndCmuxVariables() {
        let env = [
            "PATH": "/usr/bin", "HOME": "/Users/x", "GIT_EDITOR": "true",
            "CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "1", "CLAUDE_CODE_SESSION_ID": "abc",
            "CLAUDE_PID": "42", "CLAUDE_CONFIG_DIR": "/Users/x/.claude-profiles/p2", "CLAUDE_EFFORT": "high",
            "AI_AGENT": "claude-code", "COREPACK_ENABLE_AUTO_PIN": "0",
            "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "delta",
            "CMUX_SURFACE_ID": "s1",
        ]
        #expect(TerminalEnvironment.clean(env) == ["PATH": "/usr/bin", "HOME": "/Users/x"])
    }

    @Test func keepsUsersOwnGitEditor() {
        #expect(TerminalEnvironment.clean(["GIT_EDITOR": "nvim"]) == ["GIT_EDITOR": "nvim"])
    }
}
