# Isolated AI Dev VM Setup

This guide describes a VM-based development workflow for `wifi-wand` when you want stronger isolation than a standard devcontainer provides.

The core idea is:

- keep the project source code inside a VM, not on a host bind mount
- install AI CLIs inside the VM, not on the host
- use Ansible to make the VM reproducible
- connect RubyMine to the VM over SSH

This gives you a clearer security boundary than a normal devcontainer. Later, on an Apple Silicon Mac, you can recreate the same environment by creating a new ARM64 Ubuntu VM and rerunning the same Ansible playbooks.

## Why This Approach

A standard devcontainer usually mounts the host project tree into the container. That is good for reproducible tooling, but it is not a strong host filesystem isolation boundary.

A VM is a better fit if your goal is:

- AI tools should not see arbitrary host files
- the repo should live in an isolated guest filesystem
- the dev box should be long-lived
- the environment should be rebuildable from code

## High-Level Plan

1. Create an Ubuntu VM on the Linux host with KVM/libvirt/virt-manager.
2. Install a minimal guest OS with SSH enabled.
3. Create an Ansible control repo on the host.
4. Use Ansible to install your development stack in the guest.
5. Clone `wifiwand` inside the guest.
6. Connect RubyMine to the guest over SSH and work there.
7. Later, on the M2 Mac, create a fresh Ubuntu ARM64 VM and rerun the same Ansible playbooks.

## Step 1: Install VM Tooling on This Ubuntu Host

Ubuntu’s current virtualization docs recommend KVM/libvirt for Linux hosts and `virt-manager` for GUI management.

Run on the host:

```bash
sudo apt update
sudo apt install -y cpu-checker qemu-kvm libvirt-daemon-system virt-manager
```

Verify hardware virtualization:

```bash
kvm-ok
```

Add your user to the `libvirt` group:

```bash
sudo adduser "$USER" libvirt
```

Then log out and back in.

References:

- Ubuntu libvirt guide: <https://documentation.ubuntu.com/server/how-to/virtualisation/libvirt/>
- Ubuntu virt-manager guide: <https://documentation.ubuntu.com/server/how-to/virtualisation/virtual-machine-manager/>

## Step 2: Create the First VM

For the first VM, use a normal Ubuntu Server install. Do not over-automate the first bootstrapping pass.

Recommended VM sizing for this project and several AI CLIs:

- CPU: 4 vCPU
- Memory: 8 to 12 GB
- Disk: 80 to 120 GB
- Network: default NAT is fine to start

In `virt-manager`:

1. Create a new VM.
2. Use the current Ubuntu Server ISO for `amd64`.
3. Name the VM something explicit, for example `ai-dev-ubuntu-amd64`.
4. Use `qcow2` storage.
5. Enable OpenSSH Server during install.
6. Create a normal admin user, for example `kbennett`.
7. Finish the install and reboot.

Inside the VM, do initial prep:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y git curl unzip zip build-essential openssh-server
```

Confirm SSH is available:

```bash
systemctl status ssh
hostname -I
```

## Step 3: Set Up SSH Access From Host to VM

On the host, if needed:

```bash
ssh-keygen -t ed25519 -C "kbennett@ai-dev-vm"
ssh-copy-id kbennett@<vm-ip-address>
```

Test:

```bash
ssh kbennett@<vm-ip-address>
```

Do not proceed until passwordless SSH works reliably.

## Step 4: Install Ansible on the Host Control Node

Ansible is agentless. It runs on one control node and connects to the VM over SSH. The host laptop or desktop is the natural control node.

The Ansible docs recommend `pipx` as a clean installation route.

On the host:

```bash
sudo apt update
sudo apt install -y pipx
pipx ensurepath
pipx install --include-deps ansible
```

Then open a new shell and verify:

```bash
ansible --version
```

Reference:

- Ansible installation guide: <https://docs.ansible.com/projects/ansible/latest/installation_guide/index.html>

## Step 5: Create a Dedicated Ansible Repo

Do not mix VM provisioning with this application repo. Keep it separate.

Suggested location on the host:

```text
~/code/infra/ai-dev-vm
```

Suggested structure:

```text
ai-dev-vm/
  ansible.cfg
  inventory/
    hosts.yml
    group_vars/
      ai_dev_vm.yml
  playbooks/
    bootstrap.yml
  roles/
    base/
    ruby/
    ai_tools/
    dotfiles/
  collections/
  requirements.yml
  README.md
```

Create it:

```bash
mkdir -p ~/code/infra/ai-dev-vm/{inventory/group_vars,playbooks,roles,collections}
cd ~/code/infra/ai-dev-vm
```

## Step 6: Add Minimal Ansible Config

Create `ansible.cfg`:

```ini
[defaults]
inventory = inventory/hosts.yml
host_key_checking = True
retry_files_enabled = False
interpreter_python = auto_silent
roles_path = roles
collections_paths = collections
stdout_callback = yaml
```

Create `inventory/hosts.yml`:

```yaml
all:
  children:
    ai_dev_vm:
      hosts:
        wifiwand_vm:
          ansible_host: 192.168.122.50
          ansible_user: kbennett
```

Replace the IP address with the VM’s actual address.

Create `inventory/group_vars/ai_dev_vm.yml`:

```yaml
dev_user: kbennett
dev_home: "/home/{{ dev_user }}"
workspace_root: "{{ dev_home }}/code"
wifiwand_repo_url: "https://github.com/keithrbennett/wifiwand.git"
wifiwand_repo_dest: "{{ workspace_root }}/wifiwand"
```

## Step 7: Create the First Playbook

Create `playbooks/bootstrap.yml`:

```yaml
---
- name: Build isolated AI development VM
  hosts: ai_dev_vm
  become: true
  roles:
    - base
    - ruby
    - ai_tools
```

## Step 8: Build the `base` Role First

Start with system packages only. Keep the first pass boring and reliable.

Suggested `roles/base/tasks/main.yml`:

```yaml
---
- name: Install base apt packages
  ansible.builtin.apt:
    name:
      - git
      - curl
      - unzip
      - zip
      - build-essential
      - ca-certificates
      - gnupg
      - jq
      - tmux
      - zsh
      - ripgrep
      - fd-find
      - ruby-full
      - ruby-dev
      - libssl-dev
      - libreadline-dev
      - zlib1g-dev
      - libyaml-dev
      - libffi-dev
      - openssh-server
    state: present
    update_cache: true

- name: Ensure workspace root exists
  ansible.builtin.file:
    path: "{{ workspace_root }}"
    state: directory
    owner: "{{ dev_user }}"
    group: "{{ dev_user }}"
    mode: "0755"
```

This role should be enough to prove Ansible connectivity and package installation.

## Step 9: Add the `ruby` Role

Keep this simple at first. Use the distro Ruby or a version manager only if you actually need it.

Because `wifi-wand` currently requires Ruby `>= 3.2.0`, ensure your VM’s Ruby satisfies that. If the distro package is too old, install a version manager in this role instead.

Minimum tasks:

- install Bundler if it is missing
- configure gem/bundle paths for the VM user
- verify `ruby -v`, `bundle -v`, and `gem env`

Example task:

```yaml
---
- name: Install bundler
  become: false
  community.general.gem:
    name: bundler
    user_install: true
```

If you use `community.general.gem`, add `community.general` to `requirements.yml`:

```yaml
---
collections:
  - name: community.general
```

Install collections:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Step 10: Add the `ai_tools` Role

This is where you install `codex`, `claude`, `gemini`, and any related CLIs, but do it in layers:

1. Install generic prerequisites first.
2. Install one AI tool at a time.
3. Verify each tool before adding the next.

Suggested responsibilities for this role:

- install Node.js if your AI CLIs need it
- install Python tools if needed
- install CLI binaries
- create config/cache directories under the guest user’s home directory
- never embed plaintext API secrets in the repo

Do not put raw API keys in Git. Use one of:

- environment variables set manually in the VM
- a local `.env` file excluded from Git
- Ansible Vault for encrypted variables

Reference:

- Ansible Vault guide: <https://docs.ansible.com/ansible/latest/vault_guide/vault.html>

## Step 11: Run the Playbook

From the host control repo:

```bash
cd ~/code/infra/ai-dev-vm
ansible all -m ping
ansible-playbook playbooks/bootstrap.yml
```

If that succeeds, SSH to the VM and verify:

```bash
ssh kbennett@<vm-ip-address>
ruby -v
bundle -v
rg --version
```

Do not clone `wifi-wand` until the base toolchain is correct.

## Step 12: Clone `wifi-wand` Inside the VM

SSH into the guest and clone the repo into the guest filesystem:

```bash
mkdir -p ~/code
cd ~/code
git clone https://github.com/keithrbennett/wifiwand.git
cd wifiwand
bundle install
bundle exec rspec --version
```

At this point the repo is isolated inside the VM and is not using the host project directory.

## Step 13: Connect RubyMine to the VM Over SSH

Use RubyMine remote development over SSH instead of a devcontainer for this workflow.

High-level steps:

1. Ensure SSH to the VM works from the host.
2. In RubyMine, choose Remote Development.
3. Create a new SSH connection to the VM.
4. Point RubyMine at the project path inside the VM, for example:
   - `/home/kbennett/code/wifiwand`
5. Let RubyMine deploy or start its backend in the VM.

References:

- RubyMine remote development overview: <https://www.jetbrains.com/help/ruby/remote-development-overview.html>
- RubyMine SSH setup: <https://www.jetbrains.com/help/ruby/running-ssh-terminal.html>
- RubyMine remote server connection flow: <https://www.jetbrains.com/help/ruby/remote-development-starting-page.html>

## Step 14: Decide What Lives in Git and What Does Not

Good candidates for Git in the Ansible repo:

- `ansible.cfg`
- inventory templates
- playbooks
- role definitions
- package/tool install tasks
- shell/bootstrap scripts
- non-secret dotfiles

Do not commit:

- API keys
- SSH private keys
- `.env` files with secrets
- machine-specific state

Use `ansible-vault` or your preferred secret manager for anything sensitive.

## Step 15: Rebuild Workflow

Once the first VM is working, your normal rebuild workflow should be:

1. Create a new Ubuntu VM.
2. Enable SSH.
3. Add its IP and username to `inventory/hosts.yml`.
4. Run `ansible-playbook playbooks/bootstrap.yml`.
5. Clone `wifiwand` inside the VM.
6. Connect RubyMine over SSH.

That is the real portability story, not copying a VM image around forever.

## Step 16: Later on the M2 Mac

On Apple Silicon, do not plan around moving this exact Linux `amd64` VM image to the Mac.

Instead:

1. Create a new Ubuntu ARM64 VM on the Mac.
2. Reuse the same Ansible repo.
3. Run the same playbook against the new VM.
4. Fix any architecture-specific package or tool assumptions in Ansible.

UTM is a practical local VM option on Apple Silicon. Its docs note:

- Apple Virtualization works only when guest architecture matches host architecture.
- For Linux on Apple Silicon, use `aarch64`/ARM64 for best results.
- Rosetta is available for some `x86_64` Linux executable compatibility in Apple-virtualized Linux guests, but it should be a fallback, not your base plan.

References:

- UTM Apple settings overview: <https://docs.getutm.app/settings-apple/settings-apple/>
- UTM QEMU system docs: <https://docs.getutm.app/settings-qemu/system/>
- UTM Rosetta docs: <https://docs.getutm.app/advanced/rosetta/>

## Recommended Policy

Use this policy to keep the setup sane:

- Host machine: hypervisor, SSH keys, Ansible control repo, RubyMine UI
- Guest VM: project repo, Ruby/Bundler, AI CLIs, shell config, build tools
- Git: playbooks, roles, templates, non-secret config
- Secret storage: Ansible Vault or an external secret manager

## First Practical Milestone

Do not try to automate everything on day one.

Aim for this milestone first:

1. Create one Ubuntu VM.
2. SSH into it from the host.
3. Install Ansible on the host.
4. Use Ansible to install basic packages in the VM.
5. Clone `wifiwand` inside the VM.
6. Run `bundle install` and `bundle exec rspec --version` in the VM.
7. Connect RubyMine over SSH.

Once that works, add AI tools one at a time.
