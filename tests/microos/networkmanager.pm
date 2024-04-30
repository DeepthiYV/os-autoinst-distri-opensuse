# SUSE's openQA tests
#
# Copyright 2016-2024 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Test NetworkManager on SLE Micro/MicroOS environments
# Maintainer: QE Core <qe-core@suse.de>

use Mojo::Base "consoletest";
use testapi;
use utils;
use transactional;
use Utils::Architectures qw(is_s390x);

my (%network_s390x, %network_qemu, %net_config, $nic_name);

sub ping_check {
    assert_script_run("ping -c 5 $net_config{'dhcp_server'}");
    assert_script_run("ping -c 5 $net_config{'dns_server'}");
    # disconnect the device, skip the test on remote worker with ssh connection
    unless (is_s390x) {
        assert_script_run("nmcli device disconnect $nic_name");
        if (script_run("ping -c 5 $net_config{'dns_server'}") == 0) {
            die('The network is still up after disconnection');
        }
        assert_script_run("nmcli device connect $nic_name");
        assert_script_run("ping -c 5 $net_config{'dhcp_server'}");
        assert_script_run("ping -c 5 $net_config{'dns_server'}");
    }
}

sub restore_config {
    script_run('rm -f /etc/NetworkManager/conf.d/00-use-dnsmasq.conf');
    script_run('unlink /etc/resolv.conf');
    systemctl('restart NetworkManager');
}

# double check what DNS-Manager is currently used by NetworkManger
sub dns_mgr {
    my $RcManager = script_output_retry(
'dbus-send --system --print-reply --dest=org.freedesktop.NetworkManager /org/freedesktop/NetworkManager/DnsManager org.freedesktop.DBus.Properties.Get string:org.freedesktop.NetworkManager.DnsManager string:RcManager',
        delay => 5,
        retry => 3
    );
    my $mode = script_output_retry(
'dbus-send --system --print-reply --dest=org.freedesktop.NetworkManager /org/freedesktop/NetworkManager/DnsManager org.freedesktop.DBus.Properties.Get string:org.freedesktop.NetworkManager.DnsManager string:Mode',
        delay => 5,
        retry => 3
    );
    return ($RcManager, $mode);
}

sub run {
    # the below network confiration is used if on s390x
    %network_s390x = (
        'dhcp_server' => '10.145.10.254',
        'dns_server' => '10.144.53.53',
        'mac_addr' => get_var('VIRSH_MAC'),
        'local_ip' => get_var('VIRSH_GUEST')
    );
    # the below network confiration is used if on qemu setups
    %network_qemu = (
        'dhcp_server' => '10.0.2.2',
        'dns_server' => '10.0.2.3',
        'mac_addr' => get_var('NICMAC'),
        'local_ip' => '10.0.2.15'
    );
    %net_config = is_s390x ? %network_s390x : %network_qemu;
    $nic_name = script_output("grep $net_config{'mac_addr'} /sys/class/net/*/address |cut -d / -f 5");

    # make sure 'sysconfig' and 'sysconfig-netconfig' are not installed by default
    my @pkgs = ('sysconfig', 'sysconfig-netconfig');
    foreach my $pkg (@pkgs) {
        die "$pkg will not be installed by default on SLE Micro" if (script_run("rpm -q $pkg") == 0);
    }
    my ($RcManager, $mode);
    # check 'NetworkManager' service is up and it can get right DNS server
    systemctl('is-active NetworkManager');
    assert_script_run('grep "Generated by NetworkManager" /etc/resolv.conf');
    assert_script_run qq(grep "nameserver $net_config{'dns_server'}" /etc/resolv.conf);
    # DNS-Manager check
    record_info('default dns bind config');
    ($RcManager, $mode) = dns_mgr();
    die 'wrong DNS-Manager is currently used for default' if ($RcManager !~ /symlink/ || $mode !~ /default/);
    ping_check;
    record_info('chronyd service check');
    script_output('chronyc -n sources');
    # basic nm cli tests
    script_run('nmcli');
    script_run('nmcli device show');
    assert_script_run qq(nmcli device show | grep GENERAL.DEVICE | grep $nic_name);
    assert_script_run qq(nmcli device show | grep IP4.ADDRESS | grep $net_config{'local_ip'});
    assert_script_run qq(nmcli device show | grep IP4.DNS | grep $net_config{'dns_server'});
    ping_check;
    # dnsmasq test
    script_output(
        'cat > /etc/NetworkManager/conf.d/00-use-dnsmasq.conf <<EOF
# This enabled the dnsmasq plugin.
[main]
dns=dnsmasq
EOF
true'
    );
    systemctl('restart NetworkManager');
    # DNS-Manager check
    record_info('with dnsmasq');
    ($RcManager, $mode) = dns_mgr();
    die 'wrong DNS-Manager is currently used for dnsmasq' if ($RcManager !~ /symlink/ || $mode !~ /dnsmasq/);
    ping_check;
    # systemd-resolved
    assert_script_run('rm -f /etc/NetworkManager/conf.d/00-use-dnsmasq.conf');
    assert_script_run('ln -rsf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf');
    systemctl('restart NetworkManager');
    record_info('with systemd-resolved');
    # DNS-Manager check
    ($RcManager, $mode) = dns_mgr();
    die 'wrong DNS-Manager is currently used for systemd-resolved' if ($RcManager !~ /unmanaged/ || $mode !~ /systemd-resolved/);
    ping_check;
    # Restore the original system config
    restore_config;
}

sub test_flags {
    return {fatal => 1};
}

sub post_fail_hook {
    restore_config;
    script_run("journalctl --no-pager -o short-precise > /tmp/full_journal.txt");
    upload_logs "/tmp/full_journal.txt";
}

1;
