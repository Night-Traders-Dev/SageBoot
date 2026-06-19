## boot.cfg parser for SageBoot
## Parses key-value settings for configuring kernel paths, timeouts, and command lines.

proc parse_config(text: String):
    let conf = {}
    let lines = split(text, "\n")
    let i = 0
    while i < len(lines):
        let line = strip(lines[i])
        if len(line) > 0 and line[0] != "#":
            let parts = split(line, "=")
            if len(parts) >= 2:
                let key = strip(parts[0])
                # Re-join remainder in case the value contains '=' signs
                let value_parts = slice(parts, 1, len(parts))
                let val = strip(join(value_parts, "="))
                conf[key] = val
        i = i + 1
    return conf

proc get_string(conf, key: String, default_val: String) -> String:
    if dict_has(conf, key):
        let val = conf[key]
        if val != nil:
            return val
    return default_val

proc get_int(conf, key: String, default_val: Int) -> Int:
    if dict_has(conf, key):
        let val = conf[key]
        if val != nil:
            let num = tonumber(val)
            if num != nil:
                return num
    return default_val
