package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestToolDefinitionCount(t *testing.T) {
	if got := len(toolDefinitions()); got != 9 {
		t.Fatalf("toolDefinitions() count = %d, want 9", got)
	}
}

func TestClickMethodSchemaAndParser(t *testing.T) {
	tool := findToolDefinition(t, "click")
	properties := tool.InputSchema["properties"].(map[string]any)
	method := properties["click_method"].(map[string]any)
	values := method["enum"].([]string)
	if strings.Join(values, ",") != "auto,accessibility,app_post,sky_click,global" {
		t.Fatalf("click_method enum = %#v", values)
	}

	for input, want := range map[string]string{
		"":              "auto",
		" AUTO ":        "auto",
		"Accessibility": "accessibility",
		"app_post":      "app_post",
		"SKY_CLICK":     "sky_click",
		"GLOBAL":        "global",
	} {
		got, err := parseClickMethod(input)
		if err != nil {
			t.Fatalf("parseClickMethod(%q): %v", input, err)
		}
		if got != want {
			t.Fatalf("parseClickMethod(%q) = %q, want %q", input, got, want)
		}
	}

	for _, input := range []string{"physical", "targeted"} {
		if _, err := parseClickMethod(input); err == nil || !strings.Contains(err.Error(), "Expected one of: auto, accessibility, app_post, sky_click, global") {
			t.Fatalf("parseClickMethod(%s) error = %v", input, err)
		}
	}
}

func TestWindowsRejectsUnsupportedGlobalClickBeforeSnapshotLookup(t *testing.T) {
	x, y := 10.0, 20.0
	result := newService().click("Notepad", "", &x, &y, 1, "left", "global")
	if !result.IsError || result.Content[0].Text != "click_method 'global' is not supported on Windows" {
		t.Fatalf("global click result = %#v", result)
	}
}

func TestWindowsRejectsUnsupportedSkyClickBeforeSnapshotLookup(t *testing.T) {
	x, y := 10.0, 20.0
	result := newService().click("Notepad", "", &x, &y, 1, "left", "sky_click")
	if !result.IsError || result.Content[0].Text != "click_method 'sky_click' is not supported on Windows" {
		t.Fatalf("sky_click result = %#v", result)
	}
}

func TestGetAppStateSchemaIncludesTextLimit(t *testing.T) {
	tool := findToolDefinition(t, "get_app_state")
	properties := tool.InputSchema["properties"].(map[string]any)
	if _, ok := properties["show_full_text"]; ok {
		t.Fatal("get_app_state schema should not expose show_full_text")
	}
	textLimit := properties["text_limit"].(map[string]any)
	anyOf := textLimit["anyOf"].([]any)
	integerLimit := anyOf[0].(map[string]any)
	if got := integerLimit["type"]; got != "integer" {
		t.Fatalf("text_limit integer type = %v, want integer", got)
	}
	if got := integerLimit["minimum"]; got != 1 {
		t.Fatalf("text_limit integer minimum = %v, want 1", got)
	}
	maxLimit := anyOf[1].(map[string]any)
	if got := maxLimit["type"]; got != "string" {
		t.Fatalf("text_limit max type = %v, want string", got)
	}
	enum := maxLimit["enum"].([]string)
	if len(enum) != 1 || enum[0] != "max" {
		t.Fatalf("text_limit enum = %#v, want [max]", enum)
	}
	maxTreeNodes := properties["max_tree_nodes"].(map[string]any)
	if got := maxTreeNodes["type"]; got != "integer" {
		t.Fatalf("max_tree_nodes type = %v, want integer", got)
	}
	if got := maxTreeNodes["minimum"]; got != 1 {
		t.Fatalf("max_tree_nodes minimum = %v, want 1", got)
	}
	maxTreeDepth := properties["max_tree_depth"].(map[string]any)
	if got := maxTreeDepth["type"]; got != "integer" {
		t.Fatalf("max_tree_depth type = %v, want integer", got)
	}
	if got := maxTreeDepth["minimum"]; got != 1 {
		t.Fatalf("max_tree_depth minimum = %v, want 1", got)
	}
	required := tool.InputSchema["required"].([]string)
	if len(required) != 1 || required[0] != "app" {
		t.Fatalf("required = %#v, want [app]", required)
	}
}

func TestParseSnapshotArgsSupportsTextLimit(t *testing.T) {
	app, textLimit, maxTreeNodes, maxTreeDepth, err := parseSnapshotArgs([]string{"--text-limit", "1000", "Notepad"})
	if err != nil {
		t.Fatal(err)
	}
	if app != "Notepad" || textLimit == nil || textLimit.runtimeValue() != 1000 || maxTreeNodes != nil || maxTreeDepth != nil {
		t.Fatalf("parseSnapshotArgs = (%q, %#v, %v, %v), want (Notepad, 1000, nil, nil)", app, textLimit, maxTreeNodes, maxTreeDepth)
	}

	app, textLimit, maxTreeNodes, maxTreeDepth, err = parseSnapshotArgs([]string{"Notepad", "--text-limit", "max"})
	if err != nil {
		t.Fatal(err)
	}
	if app != "Notepad" || textLimit == nil || textLimit.runtimeValue() != "max" || maxTreeNodes != nil || maxTreeDepth != nil {
		t.Fatalf("parseSnapshotArgs max = (%q, %#v, %v, %v), want (Notepad, max, nil, nil)", app, textLimit, maxTreeNodes, maxTreeDepth)
	}

	app, textLimit, maxTreeNodes, maxTreeDepth, err = parseSnapshotArgs([]string{"Notepad"})
	if err != nil {
		t.Fatal(err)
	}
	if app != "Notepad" || textLimit != nil || maxTreeNodes != nil || maxTreeDepth != nil {
		t.Fatalf("parseSnapshotArgs default = (%q, %#v, %v, %v), want (Notepad, nil, nil, nil)", app, textLimit, maxTreeNodes, maxTreeDepth)
	}

	app, textLimit, maxTreeNodes, maxTreeDepth, err = parseSnapshotArgs([]string{"--max-tree-nodes", "3000", "--max-tree-depth", "96", "Notepad"})
	if err != nil {
		t.Fatal(err)
	}
	if app != "Notepad" || textLimit != nil || maxTreeNodes == nil || *maxTreeNodes != 3000 || maxTreeDepth == nil || *maxTreeDepth != 96 {
		t.Fatalf("parseSnapshotArgs custom tree budget = (%q, %#v, %v, %v), want (Notepad, nil, 3000, 96)", app, textLimit, maxTreeNodes, maxTreeDepth)
	}
}

func TestParseSnapshotArgsRejectsInvalidTextLimit(t *testing.T) {
	for _, value := range []string{"0", "-1", "1.5", "full"} {
		if _, _, _, _, err := parseSnapshotArgs([]string{"--text-limit", value, "Notepad"}); err == nil || err.Error() != "--text-limit must be a positive integer or max" {
			t.Fatalf("invalid text_limit %q error = %v", value, err)
		}
	}
	if _, _, _, _, err := parseSnapshotArgs([]string{"--text-limit"}); err == nil || err.Error() != "--text-limit requires a positive integer or max value" {
		t.Fatalf("missing text_limit error = %v", err)
	}
	if _, _, _, _, err := parseSnapshotArgs([]string{"--show-full-text", "Notepad"}); err == nil || err.Error() != "unknown snapshot option: --show-full-text" {
		t.Fatalf("old show_full_text flag error = %v", err)
	}
}

func TestParseSnapshotArgsRejectsInvalidTreeBudget(t *testing.T) {
	if _, _, _, _, err := parseSnapshotArgs([]string{"--max-tree-nodes", "0", "Notepad"}); err == nil || err.Error() != "--max-tree-nodes must be a positive integer" {
		t.Fatalf("invalid max_tree_nodes error = %v", err)
	}
	if _, _, _, _, err := parseSnapshotArgs([]string{"--max-tree-depth", "1.5", "Notepad"}); err == nil || err.Error() != "--max-tree-depth must be a positive integer" {
		t.Fatalf("invalid max_tree_depth error = %v", err)
	}
	if _, _, _, _, err := parseSnapshotArgs([]string{"--max-tree-nodes"}); err == nil || err.Error() != "--max-tree-nodes requires a positive integer value" {
		t.Fatalf("missing max_tree_nodes error = %v", err)
	}
}

func TestCallSequenceStopsAfterFirstToolError(t *testing.T) {
	output, hasError, err := runCallCommand([]string{
		"--calls",
		`[{"tool":"not_a_tool"},{"tool":"list_apps"}]`,
	}, newService())
	if err != nil {
		t.Fatal(err)
	}
	if !hasError {
		t.Fatal("expected hasError")
	}
	items, ok := output.([]map[string]any)
	if !ok {
		t.Fatalf("output type = %T", output)
	}
	if len(items) != 1 {
		t.Fatalf("sequence output count = %d, want 1", len(items))
	}
}

func TestReadArgumentsAcceptsJSONObject(t *testing.T) {
	args, err := readArguments(`{"app":"Notepad","pages":2}`, "")
	if err != nil {
		t.Fatal(err)
	}
	if args["app"] != "Notepad" {
		t.Fatalf("app = %v", args["app"])
	}
	if args["pages"].(json.Number).String() != "2" {
		t.Fatalf("pages = %v", args["pages"])
	}
}

func TestElementIndexAcceptsStringAndJSONNumber(t *testing.T) {
	args, err := readArguments(`{"app":"Notepad","element_index":0}`, "")
	if err != nil {
		t.Fatal(err)
	}
	if got := optionalElementIndex(args); got != "0" {
		t.Fatalf("numeric element_index = %q, want 0", got)
	}
	if got := optionalElementIndex(map[string]any{"element_index": "14"}); got != "14" {
		t.Fatalf("string element_index = %q, want 14", got)
	}
	if got := optionalElementIndex(map[string]any{"element_index": json.Number("1.5")}); got != "" {
		t.Fatalf("fractional element_index = %q, want empty", got)
	}
}

func TestMCPInitializeResponseContainsToolsCapability(t *testing.T) {
	request := map[string]any{
		"jsonrpc": "2.0",
		"id":      float64(1),
		"method":  "initialize",
		"params":  map[string]any{},
	}
	response := handleMCPRequest(request, newService())
	result, ok := response["result"].(map[string]any)
	if !ok {
		t.Fatalf("missing result: %#v", response)
	}
	capabilities := result["capabilities"].(map[string]any)
	if _, ok := capabilities["tools"]; !ok {
		t.Fatalf("missing tools capability: %#v", capabilities)
	}
}

func TestCLIHelpMentionsWindowsRuntime(t *testing.T) {
	var out bytes.Buffer
	if err := runCLI([]string{"--help"}, &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "Open Computer Use for Windows") {
		t.Fatalf("help text did not mention Windows runtime:\n%s", out.String())
	}
}

func TestWindowsRuntimeForegroundActionsRequireOptIn(t *testing.T) {
	if !strings.Contains(windowsRuntimeScript, "OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH") {
		t.Fatal("Windows app launch fallback must remain opt-in")
	}
	if !strings.Contains(windowsRuntimeScript, "OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS") {
		t.Fatal("Windows SetFocus action must remain opt-in")
	}
	if !strings.Contains(windowsRuntimeScript, "OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK") {
		t.Fatal("Windows UIA text fallback must remain opt-in")
	}
	if !strings.Contains(serverInstructions, "does not auto-launch apps, perform SetFocus, or use UIA text fallback by default") {
		t.Fatal("MCP instructions must document the Windows background-focus policy")
	}
	if !strings.Contains(serverInstructions, "press_key activates the app's active window before sending input") {
		t.Fatal("MCP instructions must document that Windows press_key activates the target app's active window")
	}
}

func TestWindowsPressKeyUsesSystemInput(t *testing.T) {
	for _, fragment := range []string{
		"[StructLayout(LayoutKind.Explicit)]",
		"[FieldOffset(0)] public MOUSEINPUT mi;",
		"[FieldOffset(0)] public KEYBDINPUT ki;",
		"public static extern uint SendInput",
		"public static void SendKeySequence",
		"public static bool ActivateWindow",
		"AttachThreadInput(currentThread, foregroundThread, true)",
		"AttachThreadInput(currentThread, targetThread, true)",
		"[OCUWin32]::ActivateWindow($hwnd)",
		"[OCUWin32]::SendKeySequence",
		`"ctrl" = 0x11`,
		`"shift" = 0x10`,
		`"alt" = 0x12`,
		`"win" = 0x5B`,
	} {
		if !strings.Contains(windowsRuntimeScript, fragment) {
			t.Fatalf("Windows press_key runtime missing %q", fragment)
		}
	}

	start := strings.Index(windowsRuntimeScript, "function Send-Key")
	if start < 0 {
		t.Fatal("could not locate Send-Key function")
	}
	end := strings.Index(windowsRuntimeScript[start:], "function Resolve-App")
	if end < 0 {
		t.Fatal("could not locate end of Send-Key function")
	}
	if strings.Contains(windowsRuntimeScript[start:start+end], "PostMessage") {
		t.Fatal("Send-Key must not post synthetic WM_KEYDOWN/WM_KEYUP messages")
	}
}

func TestWindowsRuntimeTargetsActiveModalWindow(t *testing.T) {
	for _, fragment := range []string{
		"public static IntPtr ResolveActionWindow",
		"foregroundProcessId == processId",
		"IsWindowVisible(mainWindow) && IsWindowEnabled(mainWindow)",
		"EnumWindows(delegate(IntPtr window",
		"$hwnd = [OCUWin32]::ResolveActionWindow",
		"$latestElement = Get-MainElement $process",
		"Get-NativeWindowHandle $latestElement",
	} {
		if !strings.Contains(windowsRuntimeScript, fragment) {
			t.Fatalf("Windows modal routing runtime missing %q", fragment)
		}
	}
}

func TestWindowsRuntimeInvokesNativeDialogButtons(t *testing.T) {
	for _, fragment := range []string{
		"$BM_CLICK = 0x00F5",
		"function Test-NativeButtonClass",
		`@("Button", "CCPushButton")`,
		"function Invoke-NativeButton",
		"PostMessage($buttonHwnd, $BM_CLICK",
		"return Invoke-NativeButton $element",
		`$localizedControlType = "button"`,
		"$clickHwnd = Get-ClickWindowHandle $element $operation.element $hwnd",
	} {
		if !strings.Contains(windowsRuntimeScript, fragment) {
			t.Fatalf("Windows native button runtime missing %q", fragment)
		}
	}
}

func TestWindowsRuntimeExposesMsaaDialogNavigation(t *testing.T) {
	for _, fragment := range []string{
		"AccessibleObjectFromWindow",
		"public static object GetAccessibleClient",
		"function Get-MsaaNavigationChildren",
		`-ine "SysTreeView32"`,
		`automationId = "msaa:$($child.hwnd):$($child.childId)"`,
		`localizedControlType = "tree item"`,
		"function Invoke-MsaaElement",
		"accDoDefaultAction",
		"$handled = Invoke-MsaaElement $operation.element",
	} {
		if !strings.Contains(windowsRuntimeScript, fragment) {
			t.Fatalf("Windows MSAA navigation runtime missing %q", fragment)
		}
	}
}

func TestWindowsRuntimePreservesFocusedTextSelection(t *testing.T) {
	for _, fragment := range []string{
		"$hasKeyboardFocus = [bool]$element.Current.HasKeyboardFocus",
		"if (-not $hasKeyboardFocus)",
		"Test-TextWindowHandleCandidate $process $focused",
	} {
		if !strings.Contains(windowsRuntimeScript, fragment) {
			t.Fatalf("Windows focused text entry runtime missing %q", fragment)
		}
	}
}

func TestWindowsNavigationKeysUseExtendedKeyFlag(t *testing.T) {
	for _, fragment := range []string{
		"private static bool IsExtendedKey",
		"case 0x23: // End",
		"case 0x24: // Home",
		"case 0x2D: // Insert",
		"uint flags = IsExtendedKey(virtualKey) ? 1u : 0u",
	} {
		if !strings.Contains(windowsRuntimeScript, fragment) {
			t.Fatalf("Windows extended-key runtime missing %q", fragment)
		}
	}
}

func TestUTF8EncodingInPowerShellScript(t *testing.T) {
	// Verify that the PowerShell script sets UTF-8 encoding
	if !strings.Contains(windowsRuntimeScript, "$OutputEncoding = [System.Text.Encoding]::UTF8") {
		t.Fatal("PowerShell script must set $OutputEncoding to UTF-8 for proper non-ASCII character handling")
	}
	if !strings.Contains(windowsRuntimeScript, "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8") {
		t.Fatal("PowerShell script must set [Console]::OutputEncoding to UTF-8 for proper non-ASCII character handling")
	}
}

func TestWindowsRuntimeTextLimitSupportsMaxMode(t *testing.T) {
	if !strings.Contains(windowsRuntimeScript, "$DefaultTextLimit = 500") {
		t.Fatal("Windows runtime should define the shared 500 character text limit")
	}
	if !strings.Contains(windowsRuntimeScript, "Build-Snapshot $operation.app (Resolve-TextLimit $operation.text_limit)") {
		t.Fatal("Windows get_app_state should pass text_limit into snapshot rendering")
	}
	if !strings.Contains(windowsRuntimeScript, "$Value -is [string] -and $Value.Trim().ToLowerInvariant() -eq \"max\"") {
		t.Fatal("Windows runtime should support max text limit mode")
	}
	if !strings.Contains(windowsRuntimeScript, "([int]$operation.max_tree_nodes) ([int]$operation.max_tree_depth)") {
		t.Fatal("Windows get_app_state should pass tree budget into snapshot rendering")
	}
	if !strings.Contains(windowsRuntimeScript, "$maxLength = if ($null -eq $TextLimit) { -1 } else { [int]$TextLimit + 1 }") {
		t.Fatal("Windows selected text should use full UIA text only in max text mode")
	}
}

func TestWindowsRuntimeTreeBudgetDefaultsMatchMacOS(t *testing.T) {
	if !strings.Contains(windowsRuntimeScript, "$AccessibilityTreeMaxNodeCount = 1200") {
		t.Fatal("Windows runtime should default to the shared 1200 node tree budget")
	}
	if !strings.Contains(windowsRuntimeScript, "$AccessibilityTreeMaxDepth = 64") {
		t.Fatal("Windows runtime should default to the shared 64 level tree depth")
	}
	if !strings.Contains(windowsRuntimeScript, "$script:nextIndex -ge $script:MaxTreeNodes -or $depth -gt $script:MaxTreeDepth") {
		t.Fatal("Windows runtime should use shared tree budget constants while rendering")
	}
}

func findToolDefinition(t *testing.T, name string) toolDefinition {
	t.Helper()
	for _, tool := range toolDefinitions() {
		if tool.Name == name {
			return tool
		}
	}
	t.Fatalf("missing tool definition %q", name)
	return toolDefinition{}
}
