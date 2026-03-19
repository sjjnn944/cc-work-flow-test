@echo off
echo Checking Chrome DevTools MCP...
claude mcp list < nul 2>nul | findstr /C:"chrome-devtools" >nul
if errorlevel 1 (
    echo Installing Chrome DevTools MCP...
    claude mcp add chrome-devtools --scope user -- npx chrome-devtools-mcp@latest
)

echo Starting Claude...
claude.cmd --dangerously-skip-permissions
