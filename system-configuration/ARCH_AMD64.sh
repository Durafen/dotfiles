sudo ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
sudo hwclock --systohc
echo 'en_GB.UTF-8 UTF-8' | sudo tee /etc/locale.gen
sudo locale-gen

# replace ssh config if password authentication is enabled (on by default)
if ! sudo grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config; then
    sudo cp system-configuration/etc/sshd_config /etc/ssh/
    sudo systemctl restart ssh
fi

# TODO keyboard layout in X
# TODO keyboard layout in wayland
# TODO keyboard repeat in X
# TODO keyboard repeat in wayland
# TODO map caps lock to esc in X
# TODO map caps lock to esc in wayland
# TODO map caps lock to esc in console

# keyboard repeat rates console
cat <<- EOF | sudo tee /etc/systemd/system/kbdrate.service
    [Unit]
    Description=Keyboard repeat rate in tty.

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    StandardInput=tty
    StandardOutput=tty
    ExecStart=/usr/bin/kbdrate -s -d 200 -r 30

    [Install]
    WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kbdrate.service
sudo systemctl start kbdrate.service

# keyboard layout in console
# TODO replace with custom keymap
# https://wiki.archlinux.org/index.php/Linux_console/Keyboard_configuration
echo 'KEYMAP=uk' | sudo tee /etc/vconsole.conf > /dev/null

# browserpass config
sudo mkdir -p /usr/lib/mozilla/native-messaging-hosts/
sudo cp etc/firefox/com.github.browserpass.native.json /usr/lib/mozilla/native-messaging-hosts/
