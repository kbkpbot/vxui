# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.0.x   | :white_check_mark: |

## Reporting a Vulnerability

We take the security of vxui seriously. If you believe you have found a security vulnerability, please report it to us as described below.

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **kbkpbot@gmail.com**

Please include the following information in your report:

- **Description**: Clear description of the vulnerability
- **Impact**: What could an attacker do with this vulnerability?
- **Steps to Reproduce**: Detailed steps to reproduce the issue
- **Affected Versions**: Which versions are affected?
- **Environment**: OS, browser, V version
- **Possible Solutions**: If you have suggestions for fixes

### Response Timeline

We will acknowledge receipt of your vulnerability report within 48 hours and will send a more detailed response within 72 hours indicating the next steps in handling your report.

After the initial reply to your report, we will endeavor to keep you informed of the progress towards a fix and full announcement.

### What to Expect

1. **Acknowledgment**: We'll confirm receipt of your report
2. **Investigation**: We'll investigate and validate the vulnerability
3. **Fix Development**: We'll work on a fix
4. **Release**: We'll release a patched version
5. **Disclosure**: We'll publicly disclose the vulnerability (with credit to you, if desired)

### Security Best Practices

When using vxui in your applications:

#### 1. Always Escape User Input

```v
import vxui

fn (mut app App) handler(msg map[string]json2.Any) string {
    user_input := msg['name'] or { '' }.str()
    // Always escape user input!
    safe_input := vxui.escape_html(user_input)
    return '<div>Hello ${safe_input}</div>'
}
```

#### 2. Validate File Paths

```v
// vxui automatically sanitizes paths, but you can also do it manually
safe_path := vxui.sanitize_path(user_provided_path) or {
    return '<div>Invalid path</div>'
}
```

#### 3. Don't Trust Client-Side Data

All data from the frontend should be validated:

```v
fn (mut app App) update(msg map[string]json2.Any) string {
    params := msg['parameters'] or { json2.Null{} }.as_map()
    
    // Validate required fields
    if email := params['email'] {
        if !vxui.is_valid_email(email.str()) {
            return '<div class="error">Invalid email</div>'
        }
    }
    
    // Process valid data
    return '<div>Success</div>'
}
```

### Security Features in vxui

vxui includes several built-in security measures:

- **Path Sanitization**: Prevents directory traversal attacks
- **HTML Escaping**: Built-in functions to prevent XSS
- **Localhost Binding**: WebSocket server only binds to localhost
- **No External HTTP**: No external network exposure

### Known Limitations

- **Alpha Software**: vxui is in alpha stage; security features are still being enhanced
- **No CSRF Protection**: Currently no built-in CSRF token system
- **No Rate Limiting**: Built-in rate limiting is not yet implemented

We recommend:
- Validating all user inputs
- Using HTTPS if deploying to production (when supported)
- Implementing additional rate limiting for production use

## Security Updates

Security updates will be released as patch versions (e.g., 0.0.1 → 0.0.2).

To stay updated:
- Watch this repository on GitHub
- Check the [Releases](https://github.com/kbkpbot/vxui/releases) page
- Subscribe to security advisories

## Credits

We thank the following individuals who have reported security issues:

*(List will be updated as reports are received)*

---

This security policy is subject to change. Please review it periodically for updates.
