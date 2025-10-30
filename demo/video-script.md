# WiFi-Wand: 5-Minute Video Introduction Script

**Total Duration: ~5 minutes**

---

## Opening (30 seconds)

**[SCREEN: Terminal with clear prompt]**

**Narrator:** "Welcome to WiFi-Wand, a cross-platform Ruby gem that makes WiFi management simple and powerful. Whether you're on macOS or Ubuntu Linux, WiFi-Wand provides a unified interface for all your wireless networking needs."

**[Type command]**
```bash
gem install wifi-wand
```

**Narrator:** "Let's dive right into using WiFi-Wand from the command line and interactive shell."

---

## Part 1: Basic Command Line Usage (1 minute 30 seconds)

**[SCREEN: Clear terminal]**

**Narrator:** "First, let's explore basic WiFi information commands."

**[Type and execute]**
```bash
wifi-wand --help
```

**[Sample Output]**
```
Command Line Switches:                    [wifi-wand version 3.0.0-alpha.1]

-o {i,j,k,p,y}            - outputs data in inspect, JSON, pretty JSON, puts, or YAML format
-s                        - run in shell mode
-v                        - verbose mode (prints OS commands and their outputs)

Commands:
a[vail_nets]              - array of names of the available networks
ci                        - connected to Internet (not just wifi on)?
co[nnect] network-name    - turns wifi on, connects to network-name
i[nfo]                    - a hash of wifi-related information
w[ifi_on]                 - is the wifi on?
...
```

**Narrator:** "Notice how commands can be abbreviated - 'i' for info, 'a' for available networks, and so on."

**[Type and execute]**
```bash
wifi-wand w
```

**[Sample Output]**
```
true
```

**Narrator:** "WiFi is on. Let's check our current connection info."

**[Type and execute]**
```bash
wifi-wand i
```

**[Sample Output]**
```
{
          "network" => "CafeBleu_5G",
        "interface" => "wlp0s20f3",
      "ip_address" => "192.168.1.105",
     "mac_address" => "aa:bb:cc:dd:ee:ff",
          "router" => "192.168.1.1",
    "nameservers" => ["192.168.1.1", "8.8.8.8"]
}
```

**Narrator:** "Great! We're connected to 'CafeBleu_5G' with IP address 192.168.1.105."

**[Type and execute]**
```bash
wifi-wand a
```

**[Sample Output]**
```
[
    [0] "CafeBleu_5G",
    [1] "CoffeeShop_Guest", 
    [2] "HomeNetwork_2.4G",
    [3] "LibraryWiFi",
    [4] "xfinitywifi"
]
```

**Narrator:** "Here are all the networks we can see. Let's check if we have internet connectivity."

**[Type and execute]**
```bash
wifi-wand ci
```

**[Sample Output]**
```
true
```

---

## Part 2: Output Formats (45 seconds)

**Narrator:** "WiFi-Wand supports multiple output formats for integration with other tools."

**[Type and execute]**
```bash
wifi-wand i -o json
```

**[Sample Output]**
```json
{"network":"CafeBleu_5G","interface":"wlp0s20f3","ip_address":"192.168.1.105","mac_address":"aa:bb:cc:dd:ee:ff","router":"192.168.1.1","nameservers":["192.168.1.1","8.8.8.8"]}
```

**[Type and execute]**
```bash
wifi-wand a -o yaml
```

**[Sample Output]**
```yaml
---
- CafeBleu_5G
- CoffeeShop_Guest
- HomeNetwork_2.4G
- LibraryWiFi
- xfinitywifi
```

**Narrator:** "Perfect for scripting and automation!"

---

## Part 3: Interactive Shell Mode (2 minutes)

**Narrator:** "Now let's explore the real power of WiFi-Wand: interactive shell mode."

**[Type and execute]**
```bash
wifi-wand shell
```

**[Sample Output]**
```
[1] pry(#<WifiWand::CommandLineInterface>)> 
```

**Narrator:** "We're now in an interactive Ruby shell with all WiFi-Wand commands available. This is perfect for exploration and combining commands. Let's save our WiFi info in a variable."

**[Type in shell]**
```ruby
wifi_info = info
```

**[Sample Output]**
```ruby
{
          "network" => "CafeBleu_5G",
        "interface" => "wlp0s20f3", 
      "ip_address" => "192.168.1.105",
     "mac_address" => "aa:bb:cc:dd:ee:ff",
          "router" => "192.168.1.1",
    "nameservers" => ["192.168.1.1", "8.8.8.8"]
}
```

**Narrator:** "In shell mode, we get nicely formatted output using Ruby's awesome_print gem. Now we can use that data in Ruby expressions."

**[Type in shell]**
```ruby
"My IP address is #{wifi_info['ip_address']}"
```

**[Sample Output]**
```ruby
=> "My IP address is 192.168.1.105"
```

**Narrator:** "We can manipulate the data using full Ruby syntax. Let's look at preferred networks."

**[Type in shell]**
```ruby
preferred = pref_nets
```

**[Sample Output]**
```ruby
[
    [0] "CafeBleu_5G",
    [1] "HomeNetwork_5G", 
    [2] "OfficeWiFi",
    [3] "LibraryWiFi",
    [4] "Hotel_Guest"
]
```

**[Type in shell]**
```ruby
"I have #{preferred.size} saved networks"
```

**[Sample Output]**
```ruby
=> "I have 5 saved networks"
```

**Narrator:** "Let's look up the password for our current network. Commands can be abbreviated - we can use 'pa' for password and 'ne' for network_name."

**[Type in shell]**
```ruby
password(network_name)
```

**[Sample Output]**
```ruby
=> "my_cafe_password_123"
```

**Narrator:** "And here's the abbreviated version - much faster to type:"

**[Type in shell]**
```ruby
pa(ne)
```

**[Sample Output]**
```ruby
=> "my_cafe_password_123"
```

---

## Part 4: Advanced Features (45 seconds)

**Narrator:** "WiFi-Wand includes some advanced features for network management."

**[Type in shell]**
```ruby
# Check current nameservers
nameservers
```

**[Sample Output]**
```ruby
[
    [0] "192.168.1.1",
    [1] "8.8.8.8"
]
```

**Narrator:** "We can modify nameservers too. Let's clear them first, then set custom ones using the abbreviated form."

**[Type in shell]**
```ruby
# Clear all nameservers
na :clear
```

**[Sample Output]**
```ruby
=> []
```

**[Type in shell]**
```ruby
# Set new nameservers (Cloudflare and Google)
na '1.1.1.1', '8.8.8.8'
```

**[Sample Output]**
```ruby
=> ["1.1.1.1", "8.8.8.8"]
```

**[Type in shell]**
```ruby
# Remove a network from saved networks
forget "Hotel_Guest"
```

**[Sample Output]**
```ruby
=> ["Hotel_Guest"]
```

**Narrator:** "We can also remove multiple networks at once. Now let's see the 'till' command - it waits for a specific network state and can run a block while waiting."

**[Type in shell]**
```ruby
till :conn { puts "#{Time.now}: Waiting for connection..." }
```

**[Sample Output]**
```ruby
2024-08-23 14:32:15 -0700: Waiting for connection...
2024-08-23 14:32:16 -0700: Waiting for connection...
=> true
```

**Narrator:** "You can also shell out to run other commands by prefixing with a dot."

**[Type in shell]**
```ruby
.ping -c 1 google.com
```

**[Sample Output]**
```
PING google.com (172.217.164.110): 56 data bytes
64 bytes from 172.217.164.110: icmp_seq=0 ttl=118 time=12.345 ms
--- google.com ping statistics ---
1 packets transmitted, 1 received, 0% packet loss
```

---

## Closing (30 seconds)

**[Type in shell]**
```ruby
exit
```

**[Back to regular terminal]**

**Narrator:** "That's WiFi-Wand! A powerful, cross-platform WiFi management tool that works great both for quick command-line tasks and interactive exploration. Key features include:"

**[SCREEN: Text overlay while narrator speaks]**
- ✅ Cross-platform support (macOS & Ubuntu)
- 🔧 Command-line and interactive modes  
- 📊 Multiple output formats (JSON, YAML, etc.)
- 🔍 Comprehensive network information
- 🛠️ Network management capabilities

**Narrator:** "Install it with 'gem install wifi-wand' and visit github.com/keithrbennett/wifiwand for documentation. Thanks for watching!"

---

## Technical Notes for Video Production

### Screen Setup
- Use a clean terminal with good contrast
- Font size should be large enough for video (14pt minimum)
- Consider using a terminal theme with good color contrast
- Clear the screen between major sections

### Timing Breakdown
- Opening: 0:00-0:30
- Command Line Usage: 0:30-2:00  
- Output Formats: 2:00-2:45
- Interactive Shell: 2:45-4:45
- Closing: 4:45-5:15

### Sample Data Notes
- All network names, IP addresses, and passwords shown are fictional
- Real commands should be executed in a safe test environment
- Consider using a dedicated test network for demonstrations
- MAC addresses should be anonymized (aa:bb:cc:dd:ee:ff format)

### Voice Over Tips
- Speak clearly and at moderate pace
- Pause briefly after each command execution
- Emphasize key features and benefits
- Keep technical jargon minimal for broader audience

### Visual Enhancements
- Highlight important output with cursor movement
- Use text overlays for feature summaries
- Consider split-screen for complex examples  
- Add timestamps for easy navigation
