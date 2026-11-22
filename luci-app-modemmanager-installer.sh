#!/bin/sh
# ==============================================================================
# luci-app-modemmanager 一体式中文版 OpenWrt 安装器与 APK 构建脚本 (v1.0.0-r21)
# 升级说明:
#   1. 彻底解决『提示后台未运行』与『需点击短信管理才能收新短信且不自动转发』两大问题:
#      - 根因1: OpenWrt procd 在服务启动参数未变化时会忽略 restart，导致旧版(r3)监控进程一直驻留内存，
#        新版守护进程从未真正运行；同时 BusyBox ps 在非终端管道中默认截断至 79 列导致 grep 匹配失败。
#      - 根因2: save_forward_config 存在跨行字符串语法错误与未定义的 system('sleep 1') 调用。
#      - 根因3: 前端在处于“短信转发”或“AT命令”标签页时暂停了后台轮询，导致不切回“短信管理”就不刷新短信。
#      - 修复: 安装时强制清理旧进程并升级 procd 实例标识，守护进程每 5 秒主动轮询模块同步新短信并触发转发，
#        前端新增全标签页 5 秒无感后台轮询（不打断输入框焦点）与 CLI 直连兜底。
# ==============================================================================
set -e

extract_tree() {
	TARGET_DIR="$1"
	mkdir -p "$TARGET_DIR/root/usr/libexec/rpcd"
	mkdir -p "$TARGET_DIR/root/usr/bin"
	mkdir -p "$TARGET_DIR/root/etc/init.d"
	mkdir -p "$TARGET_DIR/root/usr/share/luci/menu.d"
	mkdir -p "$TARGET_DIR/root/usr/share/rpcd/acl.d"
	mkdir -p "$TARGET_DIR/htdocs/luci-static/resources/view/modemmanager"
	mkdir -p "$TARGET_DIR/po/zh_Hans"

	cat > "$TARGET_DIR/Makefile" <<'EOF_MAKEFILE'
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modemmanager
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=OpenWrt Developer <dev@openwrt.org>

LUCI_TITLE:=LuCI Support for ModemManager (SMS & Voice Call Manager)
LUCI_DESCRIPTION:=Web management interface for ModemManager supporting modem status, SMS messaging (read/send/delete), and voice call records (view/dial/hangup/delete).
LUCI_DEPENDS:=+luci-base +modemmanager +rpcd +rpcd-mod-ucode
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
EOF_MAKEFILE

	cat > "$TARGET_DIR/build-apk.sh" <<'EOF_BUILD_APK'
#!/bin/sh
# Build .apk package for OpenWrt (apk-tools v3 / APKv2 fallback)
# Reference: https://openwrt.org/docs/guide-user/network/wan/wwan/modemmanager
# Usage: sh build-apk.sh [version] [release]
set -e

PKG_NAME="luci-app-modemmanager"
PKG_VERSION="${1:-1.0.0}"
PKG_RELEASE="${2:-2}"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="${ROOT_DIR}/dist"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

DATA="$WORKDIR/data"
mkdir -p "$DATA"
cp -a "$ROOT_DIR/root/"* "$DATA/"
mkdir -p "$DATA/www/luci-static/resources/view/modemmanager"
cp -a "$ROOT_DIR/htdocs/luci-static/resources/view/modemmanager/"* "$DATA/www/luci-static/resources/view/modemmanager/"

chmod 0755 "$DATA/usr/libexec/rpcd/luci.modemmanager"
chmod 0644 "$DATA/usr/share/luci/menu.d/luci-app-modemmanager.json"
chmod 0644 "$DATA/usr/share/rpcd/acl.d/luci-app-modemmanager.json"
chmod 0644 "$DATA/www/luci-static/resources/view/modemmanager/index.js"

SCRIPTS="$WORKDIR/scripts"
mkdir -p "$SCRIPTS"

cat > "$SCRIPTS/post-install" <<'SCRIPT'
#!/bin/sh
if [ -z "${IPKG_INSTROOT}" ]; then
	sed -i 's/\r$//' /usr/libexec/rpcd/luci.modemmanager 2>/dev/null || true
	chmod 0755 /usr/libexec/rpcd/luci.modemmanager 2>/dev/null || true
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/ 2>/dev/null || true
	/etc/init.d/rpcd restart 2>/dev/null || true
	/etc/init.d/uhttpd reload 2>/dev/null || true
fi
exit 0
SCRIPT

cat > "$SCRIPTS/post-upgrade" <<'SCRIPT'
#!/bin/sh
if [ -z "${IPKG_INSTROOT}" ]; then
	sed -i 's/\r$//' /usr/libexec/rpcd/luci.modemmanager 2>/dev/null || true
	chmod 0755 /usr/libexec/rpcd/luci.modemmanager 2>/dev/null || true
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/ 2>/dev/null || true
	/etc/init.d/rpcd restart 2>/dev/null || true
	/etc/init.d/uhttpd reload 2>/dev/null || true
fi
exit 0
SCRIPT

cat > "$SCRIPTS/post-deinstall" <<'SCRIPT'
#!/bin/sh
if [ -z "${IPKG_INSTROOT}" ]; then
	rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/ 2>/dev/null || true
	/etc/init.d/rpcd restart 2>/dev/null || true
fi
exit 0
SCRIPT

chmod 0755 "$SCRIPTS"/*

mkdir -p "$OUTDIR"
APK_FILE="$OUTDIR/${PKG_NAME}_${PKG_VERSION}-r${PKG_RELEASE}_noarch.apk"

if command -v apk >/dev/null 2>&1 && apk mkpkg --help >/dev/null 2>&1; then
	apk mkpkg \
		--info "name:${PKG_NAME}" \
		--info "version:${PKG_VERSION}-r${PKG_RELEASE}" \
		--info "description:LuCI Support for ModemManager (SMS & Voice Call Manager)" \
		--info "arch:noarch" \
		--info "license:Apache-2.0" \
		--info "origin:https://openwrt.org/docs/guide-user/network/wan/wwan/modemmanager" \
		--info "url:https://www.freedesktop.org/software/ModemManager/man/latest/mmcli.1.html" \
		--info "maintainer:OpenWrt Developer <dev@openwrt.org>" \
		--info "depends:luci-base modemmanager rpcd rpcd-mod-ucode" \
		--info "provides:${PKG_NAME}=${PKG_VERSION}-r${PKG_RELEASE}" \
		--info "tags:openwrt:section=luci" \
		--script "post-install:$SCRIPTS/post-install" \
		--script "post-upgrade:$SCRIPTS/post-upgrade" \
		--script "post-deinstall:$SCRIPTS/post-deinstall" \
		--files "$DATA" \
		--output "$APK_FILE"
else
	CTRL="$WORKDIR/control"
	mkdir -p "$CTRL"
	cat > "$CTRL/.PKGINFO" <<PKGINFO
pkgname = ${PKG_NAME}
pkgver = ${PKG_VERSION}-r${PKG_RELEASE}
pkgdesc = LuCI Support for ModemManager (SMS & Voice Call Manager)
url = https://www.freedesktop.org/software/ModemManager/man/latest/mmcli.1.html
builddate = $(date +%s)
packager = OpenWrt Developer <dev@openwrt.org>
size = $(du -sb "$DATA" | awk '{print $1}')
arch = noarch
license = Apache-2.0
depend = luci-base
depend = modemmanager
depend = rpcd
depend = rpcd-mod-ucode
provides = ${PKG_NAME}=${PKG_VERSION}-r${PKG_RELEASE}
PKGINFO
	cp "$SCRIPTS/post-install" "$CTRL/.post-install"
	cp "$SCRIPTS/post-upgrade" "$CTRL/.post-upgrade"
	cp "$SCRIPTS/post-deinstall" "$CTRL/.post-deinstall"
	tar --owner=0 --group=0 -czf "$WORKDIR/control.tar.gz" -C "$CTRL" .
	tar --owner=0 --group=0 -czf "$WORKDIR/data.tar.gz" -C "$DATA" .
	cat "$WORKDIR/control.tar.gz" "$WORKDIR/data.tar.gz" > "$APK_FILE"
fi

echo "Built package: $APK_FILE"
EOF_BUILD_APK

	cat > "$TARGET_DIR/root/usr/share/luci/menu.d/luci-app-modemmanager.json" <<'EOF_MENU_JSON'
{
	"admin/modem": {
		"title": "蜂窝模块",
		"order": 35,
		"action": {
			"type": "firstchild"
		},
		"depends": {
			"acl": [ "luci-app-modemmanager" ]
		}
	},
	"admin/modem/modemmanager": {
		"title": "ModemManager 管理",
		"order": 10,
		"action": {
			"type": "view",
			"path": "modemmanager/index"
		},
		"depends": {
			"acl": [ "luci-app-modemmanager" ]
		}
	}
}
EOF_MENU_JSON

	cat > "$TARGET_DIR/root/usr/share/rpcd/acl.d/luci-app-modemmanager.json" <<'EOF_ACL_JSON'
{
	"luci-app-modemmanager": {
		"description": "Grant ubus and mmcli access for luci-app-modemmanager",
		"read": {
			"cgi-io": [ "exec" ],
			"file": {
				"/usr/bin/mmcli": [ "exec" ],
				"/usr/bin/mmcli *": [ "exec" ],
				"/usr/bin/modemmanager-sms-forwarder": [ "exec" ],
				"/usr/bin/modemmanager-sms-forwarder *": [ "exec" ],
				"/usr/libexec/rpcd/luci.modemmanager": [ "exec" ],
				"/usr/libexec/rpcd/luci.modemmanager *": [ "exec" ],
				"/etc/modemmanager_call_meta.json": [ "read" ],
				"/etc/modemmanager_at_presets.json": [ "read" ],
				"/etc/modemmanager_sms_forward.json": [ "read" ],
				"/tmp/modemmanager_forward.log": [ "read" ],
				"/etc/init.d/modemmanager": [ "read" ]
			},
			"ubus": {
				"luci.modemmanager": [
					"get_modems",
					"get_status",
					"list_sms",
					"list_calls",
					"get_at_presets",
					"get_forward_config",
					"get_forward_logs"
				],
				"file": [ "exec", "read", "stat" ]
			}
		},
		"write": {
			"cgi-io": [ "exec" ],
			"file": {
				"/usr/bin/mmcli": [ "exec" ],
				"/usr/bin/mmcli *": [ "exec" ],
				"/usr/bin/modemmanager-enable-at": [ "exec" ],
				"/usr/bin/modemmanager-sms-forwarder": [ "exec" ],
				"/usr/bin/modemmanager-sms-forwarder *": [ "exec" ],
				"/usr/libexec/rpcd/luci.modemmanager": [ "exec" ],
				"/usr/libexec/rpcd/luci.modemmanager *": [ "exec" ],
				"/etc/modemmanager_call_meta.json": [ "write" ],
				"/etc/modemmanager_at_presets.json": [ "write" ],
				"/etc/modemmanager_sms_forward.json": [ "write" ],
				"/tmp/modemmanager_forward.log": [ "write" ],
				"/tmp/mm_sms_*": [ "write" ]
			},
			"ubus": {
				"luci.modemmanager": [
					"delete_sms",
					"delete_all_sms",
					"send_sms",
					"delete_call",
					"delete_all_calls",
					"create_call",
					"call_action",
					"modem_action",
					"ussd_query",
					"send_at",
					"enable_at_debug",
					"save_at_presets",
					"save_forward_config",
					"test_forward",
					"clear_forward_logs",
				"forward_latest"
				],
				"file": [ "exec", "write", "remove" ]
			}
		}
	}
}
EOF_ACL_JSON

	cat > "$TARGET_DIR/root/usr/libexec/rpcd/luci.modemmanager" <<'EOF_RPCD'
#!/usr/bin/env ucode
'use strict';

import { stdin, popen, readfile, writefile, stat } from 'fs';

const CALL_META_FILE = '/etc/modemmanager_call_meta.json';
const PATH_PREFIX = 'PATH=/usr/sbin:/usr/bin:/sbin:/bin ';

const CN_PLMN_MAP = {
	'46000': '中国移动 (CMCC)',
	'46002': '中国移动 (CMCC)',
	'46004': '中国移动 (CMCC)',
	'46007': '中国移动 (CMCC)',
	'46008': '中国移动 (CMCC)',
	'46001': '中国联通 (CUCC)',
	'46006': '中国联通 (CUCC)',
	'46009': '中国联通 (CUCC)',
	'46003': '中国电信 (CTCC)',
	'46005': '中国电信 (CTCC)',
	'46011': '中国电信 (CTCC)',
	'46015': '中国广电 (CBN)',
	'46020': '中国铁通 (CRTC)'
};

function to_lower(str) {
	let s = '' + (str ?? '');
	let out = '';
	let len = length(s);
	for (let i = 0; i < len; i++) {
		let ch = substr(s, i, 1);
		let b = ord(ch);
		if (b >= 65 && b <= 90) out += chr(b + 32);
		else out += ch;
	}
	return out;
}

function to_upper(str) {
	let s = '' + (str ?? '');
	let out = '';
	let len = length(s);
	for (let i = 0; i < len; i++) {
		let ch = substr(s, i, 1);
		let b = ord(ch);
		if (b >= 97 && b <= 122) out += chr(b - 32);
		else out += ch;
	}
	return out;
}

function last_index_of_char(str, target_ch) {
	let s = '' + (str ?? '');
	for (let i = length(s) - 1; i >= 0; i--) {
		if (substr(s, i, 1) === target_ch) return i;
	}
	return -1;
}

function shell_quote(str) {
	if (str == null) return "''";
	let s = '' + str;
	return "'" + replace(s, /'/g, "'\\''") + "'";
}

function clean_index(val, fallback) {
	if (val == null || val === '') return fallback;
	let s = trim('' + val);
	let m = match(s, /\/([0-9]+)$/);
	if (m) return m[1];
	let m2 = match(s, /\/Modem\/([0-9]+)/);
	if (m2) return m2[1];
	if (match(s, /^[0-9]+$/)) return s;
	return fallback;
}

function run_cmd(cmd) {
	let fp = popen(PATH_PREFIX + cmd + ' 2>&1', 'r');
	if (!fp) return { code: -1, output: '无法执行系统命令' };
	let out = fp.read('all') || '';
	let code = fp.close();
	return { code: code ?? 0, output: trim(out) };
}

function run_cmd_stdout(cmd) {
	let fp = popen(PATH_PREFIX + cmd + ' 2>/dev/null', 'r');
	if (!fp) return { code: -1, output: '' };
	let out = fp.read('all') || '';
	let code = fp.close();
	return { code: code ?? 0, output: trim(out) };
}

function run_mmcli_json(args) {
	let res = run_cmd_stdout('mmcli ' + args + ' -J');
	if (res.output) {
		let raw = res.output;
		let start = index(raw, '{');
		let end = last_index_of_char(raw, '}');
		if (start >= 0 && end > start) {
			raw = substr(raw, start, end - start + 1);
		}
		try {
			let parsed = json(raw);
			if (type(parsed) == 'object') {
				return { ok: true, data: parsed, raw: raw };
			}
		} catch (e) {}
	}
	return { ok: false, data: null, raw: res.output, code: res.code };
}

function run_mmcli_kv(args) {
	let res = run_cmd_stdout('mmcli ' + args + ' -K');
	let kv = {};
	if (res.output) {
		for (let line in split(res.output, '\n')) {
			let parts = match(line, /^([^:]+)[ \t]*:[ \t]*(.*)$/);
			if (parts) {
				let k = trim(parts[1]);
				let v = trim(parts[2]);
				if (v !== '' && v !== '--') kv[k] = v;
			}
		}
	}
	return { ok: length(keys(kv)) > 0, data: kv, raw: res.output };
}

function val_or(v, fallback) {
	if (v == null || v === '' || v === '--' || v === 'unknown') return fallback;
	return v;
}

function dedup_model(manufacturer, model) {
	let man = trim('' + (manufacturer || ''));
	let mod = trim('' + (model || ''));
	if (man !== '' && mod !== '') {
		let lman = to_lower(man);
		let lmod = to_lower(mod);
		if (index(lmod, lman + ' ') === 0) {
			mod = trim(substr(mod, length(man)));
		}
	}
	return mod !== '' ? mod : man;
}

function codepoint_to_utf8(cp) {
	if (cp <= 0x7F) {
		return chr(cp);
	} else if (cp <= 0x7FF) {
		return chr(0xC0 | ((cp >> 6) & 0x1F)) +
		       chr(0x80 | (cp & 0x3F));
	} else if (cp <= 0xFFFF) {
		return chr(0xE0 | ((cp >> 12) & 0x0F)) +
		       chr(0x80 | ((cp >> 6) & 0x3F)) +
		       chr(0x80 | (cp & 0x3F));
	} else if (cp <= 0x10FFFF) {
		return chr(0xF0 | ((cp >> 18) & 0x07)) +
		       chr(0x80 | ((cp >> 12) & 0x3F)) +
		       chr(0x80 | ((cp >> 6) & 0x3F)) +
		       chr(0x80 | (cp & 0x3F));
	}
	return '?';
}

function decode_ucs2_hex(hex_str) {
	if (!hex_str) return null;
	let clean = replace('' + hex_str, /[ \t\r\n]+/g, '');
	if (length(clean) < 4 || (length(clean) % 4) !== 0 || !match(clean, /^[0-9a-fA-F]+$/)) {
		return null;
	}
	let out = '';
	let total = length(clean);
	let i = 0;
	while (i < total) {
		let w1 = hex(substr(clean, i, 4));
		i += 4;
		if (w1 == null) return null;
		if (w1 === 0) continue;
		if (w1 >= 0xD800 && w1 <= 0xDBFF && (i + 4) <= total) {
			let w2 = hex(substr(clean, i, 4));
			if (w2 != null && w2 >= 0xDC00 && w2 <= 0xDFFF) {
				i += 4;
				let cp = 0x10000 + ((w1 - 0xD800) << 10) + (w2 - 0xDC00);
				out += codepoint_to_utf8(cp);
				continue;
			}
		}
		out += codepoint_to_utf8(w1);
	}
	return out;
}

function normalize_sms_text(text_val, data_val) {
	let txt = (text_val == null || text_val === '--') ? '' : ('' + text_val);
	let dat = (data_val == null || data_val === '--') ? '' : ('' + data_val);

	if (txt !== '' && length(txt) >= 8 && (length(txt) % 4) === 0 && match(txt, /^[0-9A-Fa-f]+$/)) {
		if (match(txt, /(00[2-7][0-9A-Fa-f]|[4-9][0-9A-Fa-f]{3}|30[0-9A-Fa-f]{2}|FF[0-9A-Fa-f]{2})/)) {
			let decoded = decode_ucs2_hex(txt);
			if (decoded && length(decoded) > 0) return decoded;
		}
	}

	if (txt !== '') return txt;

	if (dat !== '') {
		let decoded = decode_ucs2_hex(dat);
		if (decoded && length(decoded) > 0) {
			return decoded;
		}
		return '[二进制数据 SMS: ' + dat + ']';
	}

	return '';
}

function format_operator_cn(op_name, op_code) {
	let code = val_or(op_code, '');
	let name = val_or(op_name, '');
	if (code !== '' && CN_PLMN_MAP[code]) {
		return CN_PLMN_MAP[code];
	}
	let up = to_upper(name);
	if (up === 'CMCC' || up === 'CHINA MOBILE' || up === 'CHN-CMCC') return '中国移动 (CMCC)';
	if (up === 'CHN-UNICOM' || up === 'CUCC' || up === 'CHINA UNICOM' || up === 'UNICOM') return '中国联通 (CUCC)';
	if (up === 'CHN-CT' || up === 'CTCC' || up === 'CHINA TELECOM') return '中国电信 (CTCC)';
	if (up === 'CBN' || up === 'CHINA BROADNET') return '中国广电 (CBN)';
	return name !== '' ? name : (code !== '' ? code : '--');
}

function format_timestamp(ts) {
	if (!ts || ts === '--') return '--';
	let s = trim('' + ts);
	let m = match(s, /^([0-9]{4}-[0-9]{2}-[0-9]{2})[T ]([0-9]{2}:[0-9]{2}:[0-9]{2})/);
	if (m) return m[1] + ' ' + m[2];
	s = replace(s, 'T', ' ');
	s = replace(s, /[ \t]*\(?([+-][0-9]{2}(:?[0-9]{2})?|Z)\)?$/, '');
	return trim(s);
}

function now_iso() {
	let res = run_cmd_stdout('date "+%Y-%m-%d %H:%M:%S"');
	return (res.code === 0 && res.output) ? res.output : '--';
}

function load_call_meta() {
	let content = readfile(CALL_META_FILE);
	if (!content) return {};
	try {
		let obj = json(content);
		return (type(obj) == 'object') ? obj : {};
	} catch (e) {
		return {};
	}
}

function save_call_meta(meta) {
	try {
		writefile(CALL_META_FILE, sprintf('%J\n', meta));
	} catch (e) {}
}

function find_call_time_from_log(cid, number) {
	let pat = 'Call/' + cid;
	if (number && number !== '未知号码' && match(number, /^[0-9+]+$/)) {
		pat = pat + '|' + replace(number, '+', '\\+');
	}
	let res = run_cmd_stdout('logread | grep -E ' + shell_quote(pat) + ' | tail -n 1');
	if (res.output) {
		let m_iso = match(res.output, /([0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2})/);
		if (m_iso) return replace(m_iso[1], 'T', ' ');
		let m_ctime = match(res.output, /^([A-Z][a-z]{2}[ \t]+[A-Z][a-z]{2}[ \t]+[0-9]+[ \t]+[0-9]{2}:[0-9]{2}:[0-9]{2}[ \t]+[0-9]{4})/);
		if (m_ctime) return m_ctime[1];
	}
	return null;
}

function get_messaging_storage_info(modem_id, primary_port) {
	let def_st = '--';
	let sup_st = '--';

	let mres = run_mmcli_json('-m ' + shell_quote(modem_id) + ' --messaging-status');
	if (mres.ok && mres.data && mres.data.modem && mres.data.modem.messaging) {
		let msg = mres.data.modem.messaging;
		def_st = val_or(msg['default-storage'], '--');
		if (type(msg['supported-storages']) == 'array' && length(msg['supported-storages']) > 0) {
			let valid = [];
			for (let s in msg['supported-storages']) {
				if (s && s !== '--' && s !== 'unknown') push(valid, s);
			}
			if (length(valid) > 0) sup_st = join(', ', valid);
		}
	}

	if (def_st === '--' || sup_st === '--') {
		let tres = run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --messaging-status');
		if (tres.output) {
			let m_sup = match(tres.output, /supported storages:[ \t]*'?([^'\r\n]+)'?/);
			let m_def = match(tres.output, /default storage:[ \t]*'?([^'\r\n]+)'?/);
			if (m_sup && sup_st === '--') {
				let v = trim(m_sup[1]);
				if (v !== '--' && v !== 'unknown') sup_st = v;
			}
			if (m_def && def_st === '--') {
				let v = trim(m_def[1]);
				if (v !== '--' && v !== 'unknown') def_st = v;
			}
		}
	}

	if (def_st === '--') {
		let tres = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --messaging-list-sms');
		if (tres.output) {
			let m = match(tres.output, /\/org\/freedesktop\/ModemManager1\/SMS\/([0-9]+)/);
			if (m) {
				let sres = run_mmcli_json('-s ' + shell_quote(m[1]));
				if (sres.ok && sres.data && sres.data.sms && sres.data.sms.properties) {
					let st = val_or(sres.data.sms.properties.storage, '--');
					if (st !== '--') {
						def_st = st;
						if (sup_st === '--') sup_st = st;
					}
				}
			}
		}
	}

	if (def_st === '--' && primary_port && index(primary_port, 'cdc-wdm') >= 0) {
		def_st = 'mbim';
		sup_st = 'SIM卡 + 模块自动管理';
	}

	return {
		default_storage: def_st,
		supported_storages: sup_st
	};
}

function get_signal_and_bearer_ext(modem_id, bearer_paths) {
	let sig_ext = '';
	let sres = run_mmcli_json('-m ' + shell_quote(modem_id) + ' --signal-get');
	if (sres.ok && sres.data && sres.data.modem && sres.data.modem.signal) {
		let sig = sres.data.modem.signal;
		let nr = sig['5g'] || {};
		let lte = sig.lte || {};
		let rsrp = val_or(nr.rsrp, val_or(lte.rsrp, ''));
		let rsrq = val_or(nr.rsrq, val_or(lte.rsrq, ''));
		let snr = val_or(nr.snr, val_or(lte.snr, ''));
		let parts = [];
		if (rsrp !== '') push(parts, 'RSRP: ' + rsrp + ' dBm');
		if (snr !== '') push(parts, 'SINR: ' + snr + ' dB');
		if (rsrq !== '') push(parts, 'RSRQ: ' + rsrq + ' dB');
		if (length(parts) > 0) sig_ext = join(' | ', parts);
	} else {
		run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --signal-setup=30');
	}

	let bearer_info = '--';
	if (type(bearer_paths) == 'array' && length(bearer_paths) > 0) {
		let bid = clean_index(bearer_paths[0], null);
		if (bid != null) {
			let bres = run_mmcli_json('-b ' + shell_quote(bid));
			if (bres.ok && bres.data && bres.data.bearer) {
				let b = bres.data.bearer;
				let ipv4 = (b['ipv4-config'] && val_or(b['ipv4-config'].address, '')) || '';
				let ipv6 = (b['ipv6-config'] && val_or(b['ipv6-config'].address, '')) || '';
				let apn = (b.properties && val_or(b.properties.apn, '')) || '';
				let bparts = [];
				if (ipv4 !== '') push(bparts, ipv4);
				if (ipv6 !== '') push(bparts, ipv6);
				if (apn !== '') push(bparts, 'APN: ' + apn);
				if (length(bparts) > 0) bearer_info = join(' / ', bparts);
			}
		}
	}

	return {
		signal_ext: sig_ext,
		bearer_info: bearer_info
	};
}

function list_modems() {
	let modems = [];
	let seen = {};
	let text_hints = {};

	let tres = run_cmd('mmcli -L');
	if (tres.code !== 0 && index(tres.output, 'find the ModemManager process') >= 0) {
		run_cmd_stdout('/etc/init.d/modemmanager start </dev/null >/dev/null 2>&1');
	}
	let paths = [];
	if (tres.output) {
		for (let line in split(tres.output, '\n')) {
			let m = match(line, /(\/org\/freedesktop\/ModemManager1\/Modem\/([0-9]+))[ \t]*(\[([^\]]+)\])?[ \t]*(.*)$/);
			if (m) {
				let p = m[1];
				let id = m[2];
				if (!seen[id]) {
					seen[id] = true;
					push(paths, p);
					let man = val_or(m[4], 'Modem');
					let mod = dedup_model(man, val_or(trim(m[5] || ''), '#' + id));
					text_hints[id] = {
						manufacturer: man,
						model: mod
					};
				}
			}
		}
	}

	let jres = run_mmcli_json('-L');
	if (jres.ok && type(jres.data['modem-list']) == 'array') {
		for (let p in jres.data['modem-list']) {
			let id = clean_index(p, null);
			if (id != null && !seen[id]) {
				seen[id] = true;
				push(paths, p);
			}
		}
	}

	for (let p in paths) {
		let idx = clean_index(p, null);
		if (idx == null) continue;
		let hint = text_hints[idx] || { manufacturer: 'Modem', model: '#' + idx };
		let manufacturer = hint.manufacturer;
		let model = hint.model;
		let state = 'connected';
		let operator = '--';
		let number = '--';

		let mres = run_mmcli_json('-m ' + shell_quote(idx));
		if (mres.ok && mres.data && mres.data.modem) {
			let g = mres.data.modem.generic || {};
			let g3 = mres.data.modem['3gpp'] || {};
			manufacturer = val_or(g.manufacturer, manufacturer);
			model = dedup_model(manufacturer, val_or(g.model, model));
			state = val_or(g.state, 'connected');
			operator = format_operator_cn(g3['operator-name'], g3['operator-code']);
			if (type(g['own-numbers']) == 'array' && length(g['own-numbers']) > 0) {
				number = val_or(g['own-numbers'][0], '--');
			}
		} else {
			let kres = run_mmcli_kv('-m ' + shell_quote(idx));
			if (kres.ok) {
				let kv = kres.data;
				manufacturer = val_or(kv['modem.generic.manufacturer'], manufacturer);
				model = dedup_model(manufacturer, val_or(kv['modem.generic.model'], model));
				state = val_or(kv['modem.generic.state'], 'connected');
				operator = format_operator_cn(kv['modem.3gpp.operator-name'], kv['modem.3gpp.operator-code']);
				number = val_or(kv['modem.generic.own-numbers.value[1]'], '--');
			}
		}

		push(modems, {
			id: idx,
			path: p,
			name: trim(manufacturer + ' ' + model) + ' (模块 #' + idx + ')',
			manufacturer: manufacturer,
			model: model,
			state: state,
			operator: operator,
			number: number
		});
	}

	return { modems: modems, raw_list: tres.output };
}

function get_status(args) {
	let modems_res = list_modems();
	let modems = modems_res.modems;
	if (length(modems) === 0) {
		return {
			found: false,
			modems: [],
			error: '未检测到 ModemManager 管理的调制解调器 (mmcli -L 输出: ' + (modems_res.raw_list || '空') + ')'
		};
	}

	let req_id = clean_index(args.modem, modems[0].id);
	let modem_id = modems[0].id;
	for (let m in modems) {
		if (m.id === req_id) {
			modem_id = req_id;
			break;
		}
	}

	let mres = run_mmcli_json('-m ' + shell_quote(modem_id));
	if (mres.ok && mres.data && mres.data.modem) {
		let m = mres.data.modem;
		let g = m.generic || {};
		let g3 = m['3gpp'] || {};

		let sim_info = {
			path: val_or(g.sim, '--'),
			iccid: '--',
			imsi: '--',
			operator_name: '--',
			operator_code: '--'
		};

		let sim_id = clean_index(g.sim, null);
		if (sim_id != null) {
			let sres = run_mmcli_json('-i ' + shell_quote(sim_id));
			if (sres.ok && sres.data && sres.data.sim && sres.data.sim.properties) {
				let sp = sres.data.sim.properties;
				sim_info.iccid = val_or(sp.iccid, '--');
				sim_info.imsi = val_or(sp.imsi, '--');
				sim_info.operator_name = val_or(sp['operator-name'], '--');
				sim_info.operator_code = val_or(sp['operator-code'], '--');
			}
		}

		let own_number = '--';
		if (type(g['own-numbers']) == 'array' && length(g['own-numbers']) > 0) {
			own_number = val_or(g['own-numbers'][0], '--');
		}

		let access_tech = '--';
		if (type(g['access-technologies']) == 'array' && length(g['access-technologies']) > 0) {
			access_tech = join(', ', g['access-technologies']);
		}

		let sig_val = 0;
		let sig_recent = 'no';
		if (type(g['signal-quality']) == 'object') {
			sig_val = int(g['signal-quality'].value || 0);
			sig_recent = val_or(g['signal-quality'].recent, 'no');
		}

		let raw_op_name = val_or(g3['operator-name'], sim_info.operator_name);
		let raw_op_code = val_or(g3['operator-code'], sim_info.operator_code);
		let op_cn = format_operator_cn(raw_op_name, raw_op_code);
		let cur_state = val_or(g.state, 'connected');
		let manufacturer = val_or(g.manufacturer, modems[0].manufacturer);
		let model = dedup_model(manufacturer, val_or(g.model, modems[0].model));
		let primary_port = val_or(g['primary-port'], '--');
		let ports_str = (type(g.ports) == 'array' && length(g.ports) > 0) ? join(', ', g.ports) : primary_port;
		let drivers = (type(g.drivers) == 'array' && length(g.drivers) > 0) ? join(', ', g.drivers) : val_or(g.plugin, '');

		// Sync operator and state back into modems array so dropdown never shows [unknown]
		for (let item in modems) {
			if (item.id === modem_id) {
				item.operator = op_cn;
				item.state = cur_state;
			}
		}

		let revision = val_or(g.revision, val_or(g['hardware-revision'], val_or(g['carrier-configuration-revision'], '--')));
		if (revision === '--') {
			let sn_m = match(model, /Modem_SN:([0-9A-Za-z]+)/);
			if (sn_m && drivers !== '') {
				revision = 'SN:' + sn_m[1] + ' (驱动: ' + drivers + ')';
			} else if (drivers !== '') {
				revision = '驱动: ' + drivers + ' (' + val_or(g.plugin, 'Generic') + ')';
			}
		}

		let st_info = get_messaging_storage_info(modem_id, primary_port);
		let ext_info = get_signal_and_bearer_ext(modem_id, g.bearers);

		return {
			found: true,
			modem_id: modem_id,
			modems: modems,
			status: {
				dbus_path: val_or(m['dbus-path'], '/org/freedesktop/ModemManager1/Modem/' + modem_id),
				manufacturer: manufacturer,
				model: model,
				revision: revision,
				imei: val_or(g3.imei, val_or(g['equipment-identifier'], '--')),
				device: val_or(g.device, '--'),
				primary_port: primary_port,
				ports: ports_str,
				plugin: val_or(g.plugin, '--'),
				drivers: drivers,
				state: cur_state,
				failed_reason: val_or(g['state-failed-reason'], ''),
				power_state: val_or(g['power-state'], '--'),
				access_tech: to_upper(access_tech),
				signal_quality: sig_val,
				signal_recent: sig_recent,
				signal_ext: ext_info.signal_ext,
				bearer_info: ext_info.bearer_info,
				own_number: own_number,
				operator_name: op_cn,
				operator_code: raw_op_code,
				registration_state: val_or(g3['registration-state'], '--'),
				default_sms_storage: st_info.default_storage,
				supported_sms_storages: st_info.supported_storages,
				sim: sim_info
			}
		};
	}

	return {
		found: true,
		modem_id: modem_id,
		modems: modems,
		status: {
			dbus_path: '/org/freedesktop/ModemManager1/Modem/' + modem_id,
			manufacturer: modems[0].manufacturer,
			model: modems[0].model,
			revision: '--',
			imei: '--',
			device: '--',
			primary_port: '--',
			ports: '--',
			plugin: '--',
			state: modems[0].state,
			power_state: '--',
			access_tech: '--',
			signal_quality: 0,
			signal_recent: 'no',
			own_number: '--',
			operator_name: '--',
			operator_code: '--',
			registration_state: '--',
			default_sms_storage: 'mbim',
			supported_sms_storages: 'SIM卡 + 模块自动管理',
			sim: { path: '--', iccid: '--', imsi: '--', operator_name: '--', operator_code: '--' }
		}
	};
}

const SMS_DB_FILE = '/etc/modemmanager_sms_db.json';
const CALL_DB_FILE = '/etc/modemmanager_calls_db.json';

function load_sms_db() {
	let raw = readfile(SMS_DB_FILE);
	if (raw) {
		try {
			let d = json(raw);
			if (type(d) === 'object' && type(d.messages) === 'array') {
				if (!d.next_id || int(d.next_id) < 1) d.next_id = length(d.messages) + 1;
				if (type(d.seen_fp) !== 'object') d.seen_fp = {};
				return d;
			}
		} catch (e) {}
	}
	return { initialized: true, next_id: 1, seen_fp: {}, messages: [] };
}

function save_sms_db(db) {
	sort(db.messages, function(a, b) {
		return int(b.id) - int(a.id);
	});
	writefile(SMS_DB_FILE, sprintf('%J\n', db));
}

function load_call_db() {
	let raw = readfile(CALL_DB_FILE);
	if (raw) {
		try {
			let d = json(raw);
			if (type(d) === 'object' && type(d.calls) === 'array') {
				if (!d.next_id || int(d.next_id) < 1) d.next_id = length(d.calls) + 1;
				return d;
			}
		} catch (e) {}
	}
	return { initialized: true, next_id: 1, calls: [] };
}

function save_call_db(db) {
	sort(db.calls, function(a, b) {
		return int(b.id) - int(a.id);
	});
	writefile(CALL_DB_FILE, sprintf('%J\n', db));
}

function list_sms(args) {
	let modem_id = clean_index(args.modem, '0');
	run_cmd_stdout('/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder --once');
	let db = load_sms_db();
	let messages = db.messages || [];
	sort(messages, function(a, b) {
		return int(b.id) - int(a.id);
	});
	return {
		modem_id: modem_id,
		count: length(messages),
		messages: messages
	};
}

function delete_sms(args) {
	let modem_id = clean_index(args.modem, '0');
	let raw_ids = '' + (args.id ?? '');
	let id_list = split(raw_ids, ',');
	let del_map = {};
	let deleted = [];

	for (let item in id_list) {
		let sid = clean_index(item, null);
		if (sid == null) continue;
		del_map[sid] = true;
		push(deleted, sid);
		run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --messaging-delete-sms=' + shell_quote(sid));
	}

	let db = load_sms_db();
	let kept = [];
	for (let m in db.messages) {
		if (!del_map['' + m.id]) {
			push(kept, m);
		}
	}
	db.messages = kept;
	if (length(kept) === 0) {
		db.seen_fp = {};
		db.next_id = 1;
	}
	save_sms_db(db);

	return {
		code: 0,
		deleted: deleted,
		errors: []
	};
}

function delete_all_sms(args) {
	let modem_id = clean_index(args.modem, '0');
	let tres = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --messaging-list-sms');
	if (tres.output) {
		for (let line in split(tres.output, '\n')) {
			let m = match(line, /\/SMS\/([0-9]+)/);
			if (m) run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --messaging-delete-sms=' + shell_quote(m[1]));
		}
	}
	let db = load_sms_db();
	let count = length(db.messages);
	db.messages = [];
	db.seen_fp = {};
	db.next_id = 1;
	save_sms_db(db);

	return {
		code: 0,
		deleted_count: count,
		deleted: [],
		errors: []
	};
}

function send_sms(args) {
	let modem_id = clean_index(args.modem, '0');
	let number = trim('' + (args.number ?? ''));
	let text = '' + (args.text ?? '');

	if (number === '' || text === '') {
		return { code: 1, error: '收件人号码和短信内容不能为空' };
	}

	let tmp_file = sprintf('/tmp/mm_sms_%s.txt', modem_id);
	writefile(tmp_file, text);

	let create_arg = sprintf("number='%s'", replace(number, /'/g, ''));
	let create_cmd = sprintf(
		'mmcli -m %s --messaging-create-sms=%s --messaging-create-sms-with-text=%s',
		shell_quote(modem_id),
		shell_quote(create_arg),
		shell_quote(tmp_file)
	);
	let cres = run_cmd(create_cmd);
	run_cmd('rm -f ' + shell_quote(tmp_file));

	if (cres.code !== 0) {
		let safe_inline = sprintf("number='%s',text='%s'", replace(number, /'/g, ''), replace(text, /'/g, ''));
		cres = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --messaging-create-sms=' + shell_quote(safe_inline));
		if (cres.code !== 0) {
			return { code: 1, error: '创建短信失败: ' + cres.output };
		}
	}

	let m = match(cres.output, /\/org\/freedesktop\/ModemManager1\/SMS\/([0-9]+)/);
	if (!m) {
		return { code: 1, error: '无法解析新建短信 ID: ' + cres.output };
	}
	let sms_id = m[1];

	let sres = run_cmd('mmcli -s ' + shell_quote(sms_id) + ' --send');
	// Immediately delete from modem after send attempt and store in local DB so modem storage stays empty
	run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --messaging-delete-sms=' + shell_quote(sms_id));

	let db = load_sms_db();
	let db_id = '' + (db.next_id++);
	let ts_now = now_iso();
	push(db.messages, {
		id: db_id,
		modem_id: modem_id,
		number: number,
		text: text,
		state: (sres.code === 0) ? 'sent' : 'stored',
		storage: 'db',
		timestamp: ts_now,
		forwarded: true
	});
	save_sms_db(db);

	if (sres.code !== 0) {
		return {
			code: 1,
			id: db_id,
			error: '发送短信失败 (已转存至本地数据库草稿 #' + db_id + '，已释放模块空间): ' + sres.output
		};
	}

	return {
		code: 0,
		id: db_id,
		message: '中文/文本短信已成功发送并归档至本地数据库 (ID #' + db_id + ')'
	};
}

function list_calls(args) {
	let modem_id = clean_index(args.modem, '0');
	run_cmd_stdout('/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder --once');
	let db = load_call_db();
	let calls = db.calls || [];
	sort(calls, function(a, b) {
		return int(b.id) - int(a.id);
	});
	return {
		modem_id: modem_id,
		count: length(calls),
		calls: calls
	};
}

function delete_call(args) {
	let modem_id = clean_index(args.modem, '0');
	let raw_ids = '' + (args.id ?? '');
	let id_list = split(raw_ids, ',');
	let del_map = {};
	let deleted = [];

	for (let item in id_list) {
		let cid = clean_index(item, null);
		if (cid == null) continue;
		del_map[cid] = true;
		push(deleted, cid);
		run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --voice-delete-call=' + shell_quote(cid));
	}

	let db = load_call_db();
	let kept = [];
	for (let c in db.calls) {
		if (!del_map['' + c.id]) {
			push(kept, c);
		} else if (c.orig_id) {
			run_cmd_stdout('mmcli -m ' + shell_quote(c.modem_id || modem_id) + ' --voice-delete-call=' + shell_quote(c.orig_id));
		}
	}
	db.calls = kept;
	save_call_db(db);

	return {
		code: 0,
		deleted: deleted,
		errors: []
	};
}

function delete_all_calls(args) {
	let modem_id = clean_index(args.modem, '0');
	let tres = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --voice-list-calls');
	if (tres.output) {
		for (let line in split(tres.output, '\n')) {
			let m = match(line, /\/Call\/([0-9]+)/);
			if (m) run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --voice-delete-call=' + shell_quote(m[1]));
		}
	}
	let db = load_call_db();
	let count = length(db.calls);
	db.calls = [];
	save_call_db(db);

	return {
		code: 0,
		deleted_count: count,
		deleted: [],
		errors: []
	};
}

function create_call(args) {
	let modem_id = clean_index(args.modem, '0');
	let number = trim('' + (args.number ?? ''));
	if (!match(number, /^[0-9+*#]+$/)) {
		return { code: 1, error: '请输入有效的电话号码 (仅限数字、+、*、#)' };
	}

	let create_arg = sprintf("number='%s'", number);
	let cres = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --voice-create-call=' + shell_quote(create_arg));
	if (cres.code !== 0) {
		return { code: 1, error: '创建呼叫失败: ' + cres.output };
	}

	let m = match(cres.output, /\/org\/freedesktop\/ModemManager1\/Call\/([0-9]+)/);
	if (!m) {
		return { code: 1, error: '无法解析新建通话 ID: ' + cres.output };
	}
	let call_id = m[1];
	let sres = run_cmd('mmcli -o ' + shell_quote(call_id) + ' --start');

	let db = load_call_db();
	let db_id = '' + (db.next_id++);
	push(db.calls, {
		id: db_id,
		modem_id: modem_id,
		orig_id: call_id,
		path: '/local/db/Call/' + db_id,
		number: number,
		direction: 'outgoing',
		state: (sres.code === 0) ? 'ringing-out' : 'terminated',
		state_reason: 'outgoing-started',
		multiparty: 'no',
		audio_port: '--',
		timestamp: now_iso(),
		active_on_modem: (sres.code === 0),
		forwarded: true
	});
	save_call_db(db);

	if (sres.code !== 0) {
		run_cmd_stdout('mmcli -m ' + shell_quote(modem_id) + ' --voice-delete-call=' + shell_quote(call_id));
		return { code: 1, id: db_id, error: '发起呼叫失败: ' + sres.output };
	}

	return {
		code: 0,
		id: db_id,
		message: '正在拨号呼叫 ' + number + ' (记录 #' + db_id + ')'
	};
}

function call_action(args) {
	let modem_id = clean_index(args.modem, '0');
	let call_id = clean_index(args.id, null);
	let action = trim('' + (args.action ?? ''));
	if (call_id == null) {
		return { code: 1, error: '无效的通话 ID' };
	}

	let flag = null;
	if (action === 'accept') flag = '--accept';
	else if (action === 'hangup') flag = '--hangup';
	else if (action === 'start') flag = '--start';
	else return { code: 1, error: '不支持的通话操作: ' + action };

	let db = load_call_db();
	let target_cid = call_id;
	let matched = null;
	for (let c in db.calls) {
		if (('' + c.id) === ('' + call_id)) {
			matched = c;
			if (c.orig_id) target_cid = c.orig_id;
			break;
		}
	}

	let res = run_cmd('mmcli -o ' + shell_quote(target_cid) + ' ' + flag);
	if (matched) {
		if (action === 'accept' && res.code === 0) {
			matched.state = 'active';
			save_call_db(db);
		} else if (action === 'hangup') {
			matched.state = 'terminated';
			matched.state_reason = 'terminated';
			matched.active_on_modem = false;
			save_call_db(db);
			run_cmd_stdout('mmcli -m ' + shell_quote(matched.modem_id || modem_id) + ' --voice-delete-call=' + shell_quote(target_cid));
		}
	}
	return {
		code: res.code,
		output: res.output
	};
}

function modem_action(args) {
	let modem_id = clean_index(args.modem, '0');
	let action = trim('' + (args.action ?? ''));
	let cmd = null;

	if (action === 'enable') cmd = 'mmcli -m ' + shell_quote(modem_id) + ' -e';
	else if (action === 'disable') cmd = 'mmcli -m ' + shell_quote(modem_id) + ' -d';
	else if (action === 'reset') cmd = 'mmcli -m ' + shell_quote(modem_id) + ' -r';
	else if (action === 'scan') cmd = 'mmcli -S';
	else return { code: 1, error: '不支持的模块操作: ' + action };

	let res = run_cmd(cmd);
	return {
		code: res.code,
		output: res.output
	};
}

function ussd_query(args) {
	let modem_id = clean_index(args.modem, '0');
	let code_str = trim('' + (args.code ?? ''));
	let action = trim('' + (args.action ?? 'initiate'));

	if (action === 'cancel') {
		let res = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --3gpp-ussd-cancel');
		return { code: res.code, output: res.output };
	}
	if (action === 'status') {
		let res = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --3gpp-ussd-status');
		return { code: res.code, output: res.output };
	}
	if (code_str === '') {
		return { code: 1, error: 'USSD 指令不能为空 (例如 *101#)' };
	}

	let flag = (action === 'respond') ? '--3gpp-ussd-respond=' : '--3gpp-ussd-initiate=';
	let res = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' ' + flag + shell_quote(code_str));
	let out = res.output;
	let hex_match = match(out, /response:[ \t]*'([0-9A-Fa-f]{8,})'/);
	if (hex_match) {
		let dec = decode_ucs2_hex(hex_match[1]);
		if (dec) out += '\n[UCS-2 中文解码]: ' + dec;
	}
	return {
		code: res.code,
		output: out
	};
}

function enable_at_debug(args) {
	let res = run_cmd('/usr/bin/modemmanager-enable-at');
	return {
		code: res.code,
		output: res.output
	};
}

// Send AT command natively via ModemManager (`mmcli -m <id> --command="<AT_CMD>"`)
function send_at(args) {
	let modem_id = clean_index(args.modem, '0');
	let raw_cmd = trim('' + (args.command ?? ''));
	if (raw_cmd === '') {
		return { code: 1, error: 'AT 命令不能为空 (例如 ATI 或 AT+CSQ)' };
	}

	// Normalize leading 'at' to uppercase 'AT' so mmcli does not prepend 'AT' twice
	if (match(raw_cmd, /^[aA][tT]/)) {
		raw_cmd = 'AT' + substr(raw_cmd, 2);
	}

	let res = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --command=' + shell_quote(raw_cmd));
	if (res.code !== 0 && index(res.output, 'operation only allowed in debug mode') >= 0) {
		// Automatically enable ModemManager --debug mode and retry
		run_cmd('/usr/bin/modemmanager-enable-at');
		res = run_cmd('mmcli -m ' + shell_quote(modem_id) + ' --command=' + shell_quote(raw_cmd));
	}

	let formatted = res.output;
	let m = match(formatted, /^response:[ \t]*'(.*)'$/s);
	if (m) {
		formatted = (m[1] !== '') ? (m[1] + '\n\nOK') : 'OK';
	}

	return {
		code: res.code,
		command: raw_cmd,
		output: formatted,
		raw: res.output
	};
}

const AT_PRESETS_FILE = '/etc/modemmanager_at_presets.json';
const FORWARD_CFG_FILE = '/etc/modemmanager_sms_forward.json';
const FORWARD_LOG_FILE = '/tmp/modemmanager_forward.log';

function get_at_presets(args) {
	let raw = readfile(AT_PRESETS_FILE);
	if (raw) {
		try {
			let j = json(raw);
			if (type(j) === 'array') return { code: 0, presets: j };
			if (type(j) === 'object' && type(j.presets) === 'array') return { code: 0, presets: j.presets };
		} catch (e) {}
	}
	return { code: 0, presets: null };
}

function save_at_presets(args) {
	let list = args.presets;
	if (type(list) !== 'array') return { code: -1, error: 'presets 必须为数组' };
	writefile(AT_PRESETS_FILE, sprintf('%J\n', list));
	return { code: 0, message: '快捷 AT 指令库已保存' };
}

function get_hostname_str() {
	let h = readfile('/proc/sys/kernel/hostname');
	return h ? trim(h) : 'OpenWrt';
}

function default_forward_cfg() {
	return {
		enabled: false,
		poll_interval: 5,
		device_tag: get_hostname_str(),
		forward_calls: false,
		delete_after_forward: false,
		channels: {
			telegram: { enabled: false, bot_token: '', chat_id: '', api_host: 'https://api.telegram.org' },
			bark: { enabled: false, server_url: 'https://api.day.app', device_key: '', group: 'OpenWrt短信', sound: '' },
			serverchan: { enabled: false, sendkey: '' },
			wecom: { enabled: false, webhook_url: '' },
			dingtalk: { enabled: false, webhook_url: '' },
			feishu: { enabled: false, webhook_url: '' },
			webhook: { enabled: false, url: '', method: 'POST' }
		}
	};
}

function is_forwarder_running() {
	for (let pf in [ '/tmp/modemmanager-monitor.pid', '/tmp/modemmanager-forwarder.pid' ]) {
		let pid_raw = readfile(pf);
		if (pid_raw) {
			let pid = trim(pid_raw);
			if (match(pid, /^[0-9]+$/) && stat('/proc/' + pid)) {
				return true;
			}
		}
	}
	let ps_out = run_cmd_stdout('ps -w 2>/dev/null || ps 2>/dev/null').output;
	if (ps_out && (index(ps_out, 'modemmanager-call-monitor') >= 0 || index(ps_out, 'modemmanager-ca') >= 0)) {
		return true;
	}
	return false;
}

function ensure_forwarder_running() {
	if (is_forwarder_running()) return true;
	run_cmd_stdout('/etc/init.d/modemmanager-monitor enable </dev/null >/dev/null 2>&1');
	run_cmd_stdout('/etc/init.d/modemmanager-monitor restart </dev/null >/dev/null 2>&1');
	run_cmd_stdout('sleep 1');
	if (is_forwarder_running()) return true;
	run_cmd_stdout('start-stop-daemon -S -b -x /bin/sh -- /usr/bin/modemmanager-call-monitor --v21 </dev/null >/dev/null 2>&1');
	run_cmd_stdout('sleep 1');
	return is_forwarder_running();
}

function get_forward_config(args) {
	let cfg = default_forward_cfg();
	let raw = readfile(FORWARD_CFG_FILE);
	if (raw) {
		try {
			let j = json(raw);
			if (type(j) === 'object') {
				if (j.enabled != null) cfg.enabled = !!j.enabled;
				if (j.poll_interval != null) cfg.poll_interval = int(j.poll_interval) || 5;
				if (j.device_tag) cfg.device_tag = '' + j.device_tag;
				if (j.forward_calls != null) cfg.forward_calls = !!j.forward_calls;
				if (j.delete_after_forward != null) cfg.delete_after_forward = !!j.delete_after_forward;
				if (type(j.channels) === 'object') {
					for (let k, v in j.channels) {
						if (type(v) === 'object' && type(cfg.channels[k]) === 'object') {
							for (let fk, fv in v) {
								cfg.channels[k][fk] = fv;
							}
						}
					}
				}
			}
		} catch (e) {}
	}
	let running = ensure_forwarder_running();
	return { code: 0, running: running, config: cfg };
}

function save_forward_config(args) {
	let cfg = args.config;
	if (type(cfg) !== 'object') return { code: -1, error: '配置格式无效' };
	let raw_json = sprintf('%J', cfg);
	let res = run_cmd('/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder --save ' + shell_quote(raw_json));
	if (res.output) {
		try {
			let j = json(res.output);
			if (type(j) === 'object') return j;
		} catch (e) {}
	}
	writefile(FORWARD_CFG_FILE, raw_json + '\n');
	let running = ensure_forwarder_running();
	return {
		code: 0,
		running: running,
		message: cfg.enabled ? '短信转发配置已保存，后台监控守护进程正在运行' : '配置已保存（自动转发已关闭）'
	};
}

function test_forward(args) {
	let ch = trim('' + (args.channel || 'all'));
	let raw_json = (type(args.config) === 'object') ? sprintf('%J', args.config) : '';
	let res = run_cmd('/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder --test ' + shell_quote(ch) + ' ' + shell_quote(raw_json));
	if (res.output) {
		try {
			let j = json(res.output);
			if (type(j) === 'object') {
				return { code: j.any_ok ? 0 : 1, results: j.results || [], raw: res.output };
			}
		} catch (e) {}
	}
	return { code: res.code || 1, results: [], error: res.output || '测试命令无返回' };
}

function get_forward_logs(args) {
	let raw = readfile(FORWARD_LOG_FILE) || '';
	return { code: 0, logs: trim(raw) };
}

function clear_forward_logs(args) {
	writefile(FORWARD_LOG_FILE, '');
	return { code: 0, message: '转发日志已清空' };
}

const methods = {
	get_modems: {
		args: {},
		call: list_modems
	},
	get_status: {
		args: { modem: '0' },
		call: get_status
	},
	list_sms: {
		args: { modem: '0' },
		call: list_sms
	},
	delete_sms: {
		args: { modem: '0', id: '0' },
		call: delete_sms
	},
	delete_all_sms: {
		args: { modem: '0' },
		call: delete_all_sms
	},
	send_sms: {
		args: { modem: '0', number: 'str', text: 'str' },
		call: send_sms
	},
	list_calls: {
		args: { modem: '0' },
		call: list_calls
	},
	delete_call: {
		args: { modem: '0', id: '0' },
		call: delete_call
	},
	delete_all_calls: {
		args: { modem: '0' },
		call: delete_all_calls
	},
	create_call: {
		args: { modem: '0', number: 'str' },
		call: create_call
	},
	call_action: {
		args: { modem: '0', id: '0', action: 'str' },
		call: call_action
	},
	modem_action: {
		args: { modem: '0', action: 'str' },
		call: modem_action
	},
	ussd_query: {
		args: { modem: '0', code: 'str', action: 'str' },
		call: ussd_query
	},
	send_at: {
		args: { modem: '0', command: 'str' },
		call: send_at
	},
	enable_at_debug: {
		args: { modem: '0' },
		call: enable_at_debug
	},
	get_at_presets: {
		args: {},
		call: get_at_presets
	},
	save_at_presets: {
		args: { presets: [] },
		call: save_at_presets
	},
	get_forward_config: {
		args: {},
		call: get_forward_config
	},
	save_forward_config: {
		args: { config: {} },
		call: save_forward_config
	},
	test_forward: {
		args: { channel: 'all', config: {} },
		call: test_forward
	},
	get_forward_logs: {
		args: {},
		call: get_forward_logs
	},
	clear_forward_logs: {
		args: {},
		call: clear_forward_logs
	},
	forward_latest: {
		args: { config: {} },
		call: function(args) {
			let raw_json = (type(args.config) === 'object') ? sprintf('%J', args.config) : '';
			let res = run_cmd('/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder --forward-latest ' + shell_quote(raw_json));
			if (res.output) {
				try {
					let j = json(res.output);
					if (type(j) === 'object') {
						return { code: j.any_ok ? 0 : 1, results: j.results || [], error: j.error || '', raw: res.output };
					}
				} catch (e) {}
			}
			return { code: res.code || 1, results: [], error: res.output || '执行无返回' };
		}
	}
};

let cmd = ARGV[0];

if (cmd === '--db-delete-sms') {
	print(sprintf('%J\n', delete_sms({ modem: ARGV[1] || '0', id: ARGV[2] || '' })));
	exit(0);
}
if (cmd === '--db-clear-sms') {
	print(sprintf('%J\n', delete_all_sms({ modem: ARGV[1] || '0' })));
	exit(0);
}
if (cmd === '--db-send-sms') {
	print(sprintf('%J\n', send_sms({ modem: ARGV[1] || '0', number: ARGV[2] || '', text: ARGV[3] || '' })));
	exit(0);
}
if (cmd === '--db-delete-call') {
	print(sprintf('%J\n', delete_call({ modem: ARGV[1] || '0', id: ARGV[2] || '' })));
	exit(0);
}
if (cmd === '--db-clear-calls') {
	print(sprintf('%J\n', delete_all_calls({ modem: ARGV[1] || '0' })));
	exit(0);
}
if (cmd === '--db-create-call') {
	print(sprintf('%J\n', create_call({ modem: ARGV[1] || '0', number: ARGV[2] || '' })));
	exit(0);
}
if (cmd === '--db-call-action') {
	print(sprintf('%J\n', call_action({ modem: ARGV[1] || '0', id: ARGV[2] || '', action: ARGV[3] || '' })));
	exit(0);
}
if (cmd === '--status' || cmd === '--save' || cmd === '--test' || cmd === '--forward-latest' || cmd === '--once' || cmd === '--clear-logs' || cmd === '--init-seen' || cmd === '--sync-db') {
	let fwd_cmd = '/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder ' + shell_quote(cmd);
	if (ARGV[1] != null) fwd_cmd += ' ' + shell_quote(ARGV[1]);
	if (ARGV[2] != null) fwd_cmd += ' ' + shell_quote(ARGV[2]);
	let r = run_cmd(fwd_cmd);
	print((r.output || '{}') + '\n');
	exit(r.code);
}

if (cmd === 'list') {
	let spec = {};
	for (let k, v in methods) {
		spec[k] = v.args;
	}
	print(sprintf('%J\n', spec));
} else if (cmd === 'call') {
	let method_name = ARGV[1];
	let method = methods[method_name];
	if (!method) {
		print(sprintf('%J\n', { code: -1, error: '未知方法: ' + method_name }));
		exit(1);
	}
	let raw_in = stdin.read('all') || '{}';
	let call_args = {};
	try {
		call_args = json(raw_in) || {};
	} catch (e) {
		call_args = {};
	}
	let result = method.call(call_args);
	print(sprintf('%J\n', result));
} else {
	print(sprintf('%J\n', { error: '用法: luci.modemmanager [list|call <method>]' }));
	exit(1);
}
EOF_RPCD

	cat > "$TARGET_DIR/root/usr/bin/modemmanager-call-monitor" <<'EOF_MON_BIN'
#!/bin/sh
# Background monitor for active SMS polling, call timestamps, and automatic SMS forwarding (v1.0.0-r21)
PID_FILE="/tmp/modemmanager-monitor.pid"
FWD_CFG="/etc/modemmanager_sms_forward.json"
FWD_LOG="/tmp/modemmanager_forward.log"

echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"; exit 0' INT TERM EXIT

printf '[%s] [INFO] 后台监控与短信自动转发守护进程已启动 (PID: %s)\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'now')" "$$" >> "$FWD_LOG"

while true; do
	echo $$ > "$PID_FILE"

	# 1. Sync all SMS & Calls from modem -> Local DB (/etc/modemmanager_sms_db.json), purge modem storage, and forward new messages
	/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder --once >/dev/null 2>>"$FWD_LOG" || true

	IV=5
	if [ -f "$FWD_CFG" ]; then
		PARSED_IV=$(awk -F: '/"poll_interval"/{gsub(/[^0-9]/,"",$2); print $2; exit}' "$FWD_CFG" 2>/dev/null)
		if [ -n "$PARSED_IV" ] && [ "$PARSED_IV" -ge 2 ] 2>/dev/null && [ "$PARSED_IV" -le 60 ] 2>/dev/null; then
			IV="$PARSED_IV"
		fi
	fi

	sleep "$IV"
done
EOF_MON_BIN

	cat > "$TARGET_DIR/root/usr/bin/modemmanager-enable-at" <<'EOF_AT_BIN'
#!/bin/sh
# Enable ModemManager --debug flag so native `mmcli -m <id> --command="<AT>"` is permitted by D-Bus
INIT_FILE="/etc/init.d/modemmanager"
NEED_RESTART=0

if [ -f "$INIT_FILE" ]; then
	if ! grep -q -- '--debug' "$INIT_FILE"; then
		sed -i 's|procd_set_param command /usr/sbin/ModemManager|procd_set_param command /usr/sbin/ModemManager --debug|g' "$INIT_FILE" 2>/dev/null || true
		NEED_RESTART=1
	fi
fi

# Check if running ModemManager process already has --debug
if ! pgrep -fa ModemManager 2>/dev/null | grep -q -- '--debug'; then
	NEED_RESTART=1
fi

if [ "$NEED_RESTART" = "1" ] && [ -x "$INIT_FILE" ]; then
	"$INIT_FILE" restart >/dev/null 2>&1 || true
	# Wait up to 8 seconds for modem to re-register in mmcli -L
	i=0
	while [ $i -lt 8 ]; do
		if mmcli -L 2>/dev/null | grep -q '/Modem/'; then
			break
		fi
		sleep 1
		i=$((i + 1))
	done
fi

# Keep syslog clean by setting logging level to INFO while retaining --debug AT command permission
mmcli -G INFO >/dev/null 2>&1 || true
echo "已启用 ModemManager 原生 AT 命令支持 (--debug 模式已生效)"
EOF_AT_BIN

	cat > "$TARGET_DIR/root/etc/init.d/modemmanager-monitor" <<'EOF_MON_INIT'
#!/bin/sh /etc/rc.common
START=98
STOP=10
USE_PROCD=1

start_service() {
	procd_open_instance
	procd_set_param command /bin/sh /usr/bin/modemmanager-call-monitor --v21
	procd_set_param file /usr/bin/modemmanager-call-monitor
	procd_set_param respawn 3600 5 5
	procd_close_instance
}

stop_service() {
	if [ -f /tmp/modemmanager-monitor.pid ]; then
		kill -9 "$(cat /tmp/modemmanager-monitor.pid)" 2>/dev/null || true
		rm -f /tmp/modemmanager-monitor.pid
	fi
	for pid in $( (ps -w 2>/dev/null || ps 2>/dev/null) | awk '/[m]odemmanager-call-monitor|[m]odemmanager-ca|[m]odemmanager-forwarder/ {print $1}' ); do
		kill -9 "$pid" 2>/dev/null || true
	done
}
EOF_MON_INIT

	cat > "$TARGET_DIR/root/usr/bin/modemmanager-sms-forwarder" <<'EOF_FWD_BIN'
#!/usr/bin/env ucode
'use strict';

import { popen, readfile, writefile, unlink, stat } from 'fs';

const CONFIG_FILE = '/etc/modemmanager_sms_forward.json';
const SMS_DB_FILE = '/etc/modemmanager_sms_db.json';
const CALL_DB_FILE = '/etc/modemmanager_calls_db.json';
const LOG_FILE = '/tmp/modemmanager_forward.log';
const LOCK_FILE = '/tmp/modemmanager_forward.lock';
const DB_LOCK_FILE = '/tmp/modemmanager_db.lock';
const PATH_PREFIX = 'PATH=/usr/sbin:/usr/bin:/sbin:/bin ';

function to_lower(str) {
	let s = '' + (str ?? '');
	let out = '';
	let len = length(s);
	for (let i = 0; i < len; i++) {
		let ch = substr(s, i, 1);
		let b = ord(ch);
		if (b >= 65 && b <= 90) out += chr(b + 32);
		else out += ch;
	}
	return out;
}

function to_upper(str) {
	let s = '' + (str ?? '');
	let out = '';
	let len = length(s);
	for (let i = 0; i < len; i++) {
		let ch = substr(s, i, 1);
		let b = ord(ch);
		if (b >= 97 && b <= 122) out += chr(b - 32);
		else out += ch;
	}
	return out;
}

function last_index_of_char(str, target_ch) {
	let s = '' + (str ?? '');
	for (let i = length(s) - 1; i >= 0; i--) {
		if (substr(s, i, 1) === target_ch) return i;
	}
	return -1;
}

function shell_quote(str) {
	if (str == null) return "''";
	return "'" + replace('' + str, /'/g, "'\\''") + "'";
}

function val_or(v, fb) {
	if (v == null || v === '' || v === '--' || v === 'unknown') return fb;
	return v;
}

function run_cmd(cmd) {
	let fp = popen(PATH_PREFIX + cmd + ' 2>&1', 'r');
	if (!fp) return { code: -1, output: '' };
	let out = fp.read('all') || '';
	let code = fp.close();
	return { code: code ?? 0, output: trim(out) };
}

function run_cmd_stdout(cmd) {
	let fp = popen(PATH_PREFIX + cmd + ' 2>/dev/null', 'r');
	if (!fp) return { code: -1, output: '' };
	let out = fp.read('all') || '';
	let code = fp.close();
	return { code: code ?? 0, output: trim(out) };
}

function now_str() {
	let res = run_cmd_stdout("date '+%Y-%m-%d %H:%M:%S'");
	return (res.output !== '') ? res.output : '2026-01-01 00:00:00';
}

function now_epoch() {
	let res = run_cmd_stdout('date +%s');
	return int(res.output || '0') || 0;
}

function append_log(level, msg) {
	let line = sprintf('[%s] [%s] %s', now_str(), level, msg);
	let existing = readfile(LOG_FILE) || '';
	let lines = split(trim(existing), '\n');
	if (length(lines) === 1 && lines[0] === '') lines = [];
	push(lines, line);
	if (length(lines) > 100) {
		let trimmed = [];
		for (let i = length(lines) - 100; i < length(lines); i++) {
			push(trimmed, lines[i]);
		}
		lines = trimmed;
	}
	writefile(LOG_FILE, join('\n', lines) + '\n');
}

function get_hostname() {
	let h = readfile('/proc/sys/kernel/hostname');
	return h ? trim(h) : 'OpenWrt';
}

function is_monitor_running() {
	for (let pf in [ '/tmp/modemmanager-monitor.pid', '/tmp/modemmanager-forwarder.pid' ]) {
		let pid_raw = readfile(pf);
		if (pid_raw) {
			let pid = trim(pid_raw);
			if (match(pid, /^[0-9]+$/) && stat('/proc/' + pid)) {
				return true;
			}
		}
	}
	let ps_out = run_cmd_stdout('ps -w 2>/dev/null || ps 2>/dev/null').output;
	if (ps_out && (index(ps_out, 'modemmanager-call-monitor') >= 0 || index(ps_out, 'modemmanager-ca') >= 0)) {
		return true;
	}
	return false;
}

function ensure_monitor_running() {
	if (is_monitor_running()) return true;
	run_cmd_stdout('/etc/init.d/modemmanager-monitor enable </dev/null >/dev/null 2>&1');
	run_cmd_stdout('/etc/init.d/modemmanager-monitor restart </dev/null >/dev/null 2>&1');
	run_cmd_stdout('sleep 1');
	if (is_monitor_running()) return true;
	run_cmd_stdout('start-stop-daemon -S -b -x /bin/sh -- /usr/bin/modemmanager-call-monitor --v21 </dev/null >/dev/null 2>&1');
	run_cmd_stdout('sleep 1');
	return is_monitor_running();
}

function acquire_file_lock(lock_path, max_age) {
	let now_ts = now_epoch();
	let raw_lock = readfile(lock_path);
	if (raw_lock) {
		let lock_ts = int(trim(raw_lock)) || 0;
		if (now_ts > 0 && lock_ts > 0 && (now_ts - lock_ts) >= 0 && (now_ts - lock_ts) < max_age) {
			return false;
		}
		unlink(lock_path);
	}
	writefile(lock_path, '' + now_ts);
	return true;
}

function release_file_lock(lock_path) {
	unlink(lock_path);
}

function default_config() {
	return {
		enabled: false,
		poll_interval: 5,
		device_tag: get_hostname(),
		forward_calls: false,
		delete_after_forward: false,
		channels: {
			telegram: {
				enabled: false,
				bot_token: '',
				chat_id: '',
				api_host: 'https://api.telegram.org'
			},
			bark: {
				enabled: false,
				server_url: 'https://api.day.app',
				device_key: '',
				group: 'OpenWrt短信',
				sound: ''
			},
			serverchan: {
				enabled: false,
				sendkey: ''
			},
			wecom: {
				enabled: false,
				webhook_url: ''
			},
			dingtalk: {
				enabled: false,
				webhook_url: ''
			},
			feishu: {
				enabled: false,
				webhook_url: ''
			},
			webhook: {
				enabled: false,
				url: '',
				method: 'POST'
			}
		}
	};
}

function load_config() {
	let def = default_config();
	let raw = readfile(CONFIG_FILE);
	if (!raw) return def;
	try {
		let cfg = json(raw);
		if (type(cfg) === 'object') {
			if (cfg.enabled != null) def.enabled = !!cfg.enabled;
			if (cfg.poll_interval != null) def.poll_interval = int(cfg.poll_interval) || 5;
			if (cfg.device_tag) def.device_tag = '' + cfg.device_tag;
			if (cfg.forward_calls != null) def.forward_calls = !!cfg.forward_calls;
			if (cfg.delete_after_forward != null) def.delete_after_forward = !!cfg.delete_after_forward;
			if (type(cfg.channels) === 'object') {
				for (let k, v in cfg.channels) {
					if (type(v) === 'object' && type(def.channels[k]) === 'object') {
						for (let fk, fv in v) {
							def.channels[k][fk] = fv;
						}
					}
				}
			}
		}
	} catch (e) {}
	return def;
}

function enabled_channel_names(cfg) {
	let label_map = {
		telegram: 'Telegram',
		bark: 'Bark',
		serverchan: 'Server酱',
		wecom: '企业微信',
		dingtalk: '钉钉',
		feishu: '飞书',
		webhook: '自定义Webhook'
	};
	let list = [];
	if (cfg && type(cfg.channels) === 'object') {
		for (let ch in [ 'telegram', 'bark', 'serverchan', 'wecom', 'dingtalk', 'feishu', 'webhook' ]) {
			if (cfg.channels[ch] && cfg.channels[ch].enabled) {
				push(list, label_map[ch] || ch);
			}
		}
	}
	return list;
}

// ============================================================================
// Persistent Local SMS & Call Database (/etc/modemmanager_sms_db.json & calls)
// ============================================================================
function short_hash(str) {
	let s = '' + (str ?? '');
	let h = 2166136261;
	let len = length(s);
	for (let i = 0; i < len; i++) {
		h = ((h ^ ord(substr(s, i, 1))) * 16777619) & 0xFFFFFFFF;
	}
	return sprintf('%08x', h);
}

function make_sms_fp(number, ts, text) {
	let raw = sprintf('%s|%s|%s', trim('' + (number || '')), trim('' + (ts || '')), trim('' + (text || '')));
	return short_hash(raw);
}

function load_sms_db() {
	let raw = readfile(SMS_DB_FILE);
	if (raw) {
		try {
			let d = json(raw);
			if (type(d) === 'object' && type(d.messages) === 'array') {
				if (!d.next_id || int(d.next_id) < 1) d.next_id = length(d.messages) + 1;
				let clean_fp = {};
				for (let m in d.messages) {
					if (m) {
						clean_fp[make_sms_fp(m.number, m.timestamp, m.text)] = true;
						if (m.raw_timestamp) clean_fp[make_sms_fp(m.number, m.raw_timestamp, m.text)] = true;
					}
				}
				if (type(d.seen_fp) === 'object') {
					for (let k, v in d.seen_fp) {
						// Drop legacy full-text keys containing "|" and keep only compact 8-char hashes if messages still exist
						if (length(d.messages) > 0 && match(k, /^[0-9a-f]{8}$/)) {
							clean_fp[k] = true;
						}
					}
				}
				d.seen_fp = clean_fp;
				return d;
			}
		} catch (e) {}
	}
	return { initialized: false, next_id: 1, seen_fp: {}, messages: [] };
}

function save_sms_db(db) {
	if (type(db.seen_fp) !== 'object') db.seen_fp = {};
	let fp_keys = keys(db.seen_fp);
	if (length(fp_keys) > 600) {
		let trimmed_fp = {};
		for (let i = length(fp_keys) - 400; i < length(fp_keys); i++) {
			trimmed_fp[fp_keys[i]] = true;
		}
		db.seen_fp = trimmed_fp;
	}
	if (type(db.messages) === 'array' && length(db.messages) > 500) {
		sort(db.messages, function(a, b) {
			return int(b.id) - int(a.id);
		});
		let trimmed = [];
		for (let i = 0; i < 500; i++) {
			push(trimmed, db.messages[i]);
		}
		db.messages = trimmed;
	}
	writefile(SMS_DB_FILE, sprintf('%J\n', db));
}

function load_call_db() {
	let raw = readfile(CALL_DB_FILE);
	if (raw) {
		try {
			let d = json(raw);
			if (type(d) === 'object' && type(d.calls) === 'array') {
				if (!d.next_id || int(d.next_id) < 1) d.next_id = length(d.calls) + 1;
				return d;
			}
		} catch (e) {}
	}
	return { initialized: false, next_id: 1, calls: [] };
}

function save_call_db(db) {
	if (type(db.calls) === 'array' && length(db.calls) > 300) {
		sort(db.calls, function(a, b) {
			return int(b.id) - int(a.id);
		});
		let trimmed = [];
		for (let i = 0; i < 300; i++) {
			push(trimmed, db.calls[i]);
		}
		db.calls = trimmed;
	}
	writefile(CALL_DB_FILE, sprintf('%J\n', db));
}

function run_mmcli_json(args) {
	let res = run_cmd_stdout('mmcli ' + args + ' -J');
	if (res.output) {
		let raw = trim(res.output);
		try {
			let direct = json(raw);
			if (type(direct) === 'object') return direct;
		} catch (e1) {}
		let s = index(raw, '{');
		let e = last_index_of_char(raw, '}');
		if (s >= 0 && e > s) {
			raw = substr(raw, s, e - s + 1);
			try {
				let parsed = json(raw);
				if (type(parsed) === 'object') return parsed;
			} catch (e2) {}
		}
	}
	return null;
}

function run_mmcli_kv(args) {
	let res = run_cmd_stdout('mmcli ' + args + ' -K');
	let kv = {};
	if (res.output) {
		for (let line in split(res.output, '\n')) {
			let parts = match(line, /^([^:]+)[ \t]*:[ \t]*(.*)$/);
			if (parts) {
				let k = trim(parts[1]);
				let v = trim(parts[2]);
				if (v !== '' && v !== '--') kv[k] = v;
			}
		}
	}
	return kv;
}

function codepoint_to_utf8(cp) {
	if (cp <= 0x7F) return chr(cp);
	if (cp <= 0x7FF) return chr(0xC0 | ((cp >> 6) & 0x1F)) + chr(0x80 | (cp & 0x3F));
	if (cp <= 0xFFFF) return chr(0xE0 | ((cp >> 12) & 0x0F)) + chr(0x80 | ((cp >> 6) & 0x3F)) + chr(0x80 | (cp & 0x3F));
	if (cp <= 0x10FFFF) return chr(0xF0 | ((cp >> 18) & 0x07)) + chr(0x80 | ((cp >> 12) & 0x3F)) + chr(0x80 | ((cp >> 6) & 0x3F)) + chr(0x80 | (cp & 0x3F));
	return '?';
}

function decode_ucs2_hex(hex_str) {
	if (!hex_str) return null;
	let clean = replace('' + hex_str, /[ \t\r\n]+/g, '');
	if (length(clean) < 4 || (length(clean) % 4) !== 0 || !match(clean, /^[0-9a-fA-F]+$/)) return null;
	let out = '';
	let total = length(clean);
	let i = 0;
	while (i < total) {
		let w1 = hex(substr(clean, i, 4));
		i += 4;
		if (w1 == null) return null;
		if (w1 === 0) continue;
		if (w1 >= 0xD800 && w1 <= 0xDBFF && (i + 4) <= total) {
			let w2 = hex(substr(clean, i, 4));
			if (w2 != null && w2 >= 0xDC00 && w2 <= 0xDFFF) {
				i += 4;
				out += codepoint_to_utf8(0x10000 + ((w1 - 0xD800) << 10) + (w2 - 0xDC00));
				continue;
			}
		}
		out += codepoint_to_utf8(w1);
	}
	return out;
}

function normalize_sms_text(text_val, data_val) {
	let txt = (text_val == null || text_val === '--') ? '' : ('' + text_val);
	let dat = (data_val == null || data_val === '--') ? '' : ('' + data_val);
	if (txt !== '' && length(txt) >= 8 && (length(txt) % 4) === 0 && match(txt, /^[0-9A-Fa-f]+$/)) {
		if (match(txt, /(00[2-7][0-9A-Fa-f]|[4-9][0-9A-Fa-f]{3}|30[0-9A-Fa-f]{2}|FF[0-9A-Fa-f]{2})/)) {
			let decoded = decode_ucs2_hex(txt);
			if (decoded && length(decoded) > 0) return decoded;
		}
	}
	if (txt !== '') return txt;
	if (dat !== '') {
		let decoded = decode_ucs2_hex(dat);
		if (decoded && length(decoded) > 0) return decoded;
		return '[二进制数据 SMS: ' + dat + ']';
	}
	return '';
}

function format_timestamp(ts) {
	if (!ts || ts === '--' || ts === 'unknown') return now_str();
	let s = trim('' + ts);
	let m = match(s, /^([0-9]{4}-[0-9]{2}-[0-9]{2})[T ]([0-9]{2}:[0-9]{2}:[0-9]{2})/);
	if (m) return m[1] + ' ' + m[2];
	return s;
}

function url_encode(str) {
	let s = '' + (str || '');
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		let b = ord(c);
		if ((b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || c === '-' || c === '_' || c === '.' || c === '~') {
			out += c;
		} else {
			out += sprintf('%%%02X', b);
		}
	}
	return out;
}

function http_request(method, url, payload_obj) {
	let tmp_file = '/tmp/mm_fwd_payload.json';
	let has_curl = (run_cmd_stdout('command -v curl').code === 0);
	let has_uclient = (run_cmd_stdout('command -v uclient-fetch').code === 0);
	let has_wget = (run_cmd_stdout('command -v wget').code === 0);

	if (payload_obj != null) {
		writefile(tmp_file, sprintf('%J', payload_obj));
	}

	let cmd = '';
	if (has_curl) {
		if (method === 'GET') {
			cmd = sprintf('curl -sS -L -m 15 -w "\\n__HTTP_CODE__:%%{http_code}" %s 2>&1', shell_quote(url));
		} else {
			cmd = sprintf('curl -sS -L -m 15 -w "\\n__HTTP_CODE__:%%{http_code}" -H "Content-Type: application/json" -X POST --data-binary @%s %s 2>&1',
				shell_quote(tmp_file), shell_quote(url));
		}
	} else if (has_uclient) {
		if (method === 'GET') {
			cmd = sprintf('uclient-fetch -q -T 15 -O - %s 2>&1', shell_quote(url));
		} else {
			cmd = sprintf('uclient-fetch -q -T 15 -O - --post-file=%s --header="Content-Type: application/json" %s 2>&1',
				shell_quote(tmp_file), shell_quote(url));
		}
	} else if (has_wget) {
		if (method === 'GET') {
			cmd = sprintf('wget -q -T 15 -O - %s 2>&1', shell_quote(url));
		} else {
			cmd = sprintf('wget -q -T 15 -O - --header="Content-Type: application/json" --post-file=%s %s 2>&1',
				shell_quote(tmp_file), shell_quote(url));
		}
	} else {
		if (payload_obj != null) unlink(tmp_file);
		return { ok: false, error: '路由器未安装 curl、uclient-fetch 或 wget，无法发送 HTTP 请求' };
	}

	let fp = popen(PATH_PREFIX + cmd, 'r');
	let out = fp ? (fp.read('all') || '') : '';
	let exit_code = fp ? (fp.close() ?? 0) : -1;
	if (payload_obj != null) unlink(tmp_file);

	out = trim(out);
	let http_code = 0;
	let hm = match(out, /\n?__HTTP_CODE__:([0-9]+)$/);
	if (hm) {
		http_code = int(hm[1]);
		out = trim(replace(out, /\n?__HTTP_CODE__:[0-9]+$/, ''));
	}

	if (exit_code !== 0) {
		return { ok: false, http_code: http_code, error: out || ('请求失败 (code ' + exit_code + ')') };
	}
	if (http_code >= 400) {
		return { ok: false, http_code: http_code, error: 'HTTP ' + http_code + ': ' + out };
	}
	return { ok: true, http_code: http_code || 200, response: out };
}

function send_to_channel(ch_name, ch_cfg, msg) {
	let title = sprintf('[%s] %s', msg.device, msg.event_title);
	let body_full = sprintf("%s\n--------------------\n号码: %s\n时间: %s\n内容:\n%s",
		title, msg.number, msg.timestamp, msg.text);

	if (ch_name === 'telegram') {
		let token = trim('' + (ch_cfg.bot_token || ''));
		let chat_id = trim('' + (ch_cfg.chat_id || ''));
		let host = trim('' + (ch_cfg.api_host || 'https://api.telegram.org'));
		host = replace(host, /\/+$/, '');
		if (!token || !chat_id) return { ok: false, error: 'Telegram Bot Token 或 Chat ID 未填写' };
		let url = sprintf('%s/bot%s/sendMessage', host, token);
		let res = http_request('POST', url, {
			chat_id: chat_id,
			text: body_full
		});
		if (res.ok && res.response) {
			try {
				let j = json(res.response);
				if (j && j.ok === false) return { ok: false, error: j.description || res.response };
			} catch (e) {}
		}
		return res;
	}

	if (ch_name === 'bark') {
		let server = trim('' + (ch_cfg.server_url || 'https://api.day.app'));
		let dkey = trim('' + (ch_cfg.device_key || ''));
		server = replace(server, /\/+$/, '');
		if (!dkey) return { ok: false, error: 'Bark Device Key 未填写' };
		let url = sprintf('%s/push', server);
		let payload = {
			device_key: dkey,
			title: sprintf('%s (%s)', msg.event_title, msg.number),
			body: sprintf('%s\n[%s · %s]', msg.text, msg.device, msg.timestamp),
			group: trim('' + (ch_cfg.group || 'OpenWrt短信'))
		};
		if (ch_cfg.sound && trim('' + ch_cfg.sound) !== '') {
			payload.sound = trim('' + ch_cfg.sound);
		}
		let res = http_request('POST', url, payload);
		if (res.ok && res.response) {
			try {
				let j = json(res.response);
				if (j && j.code && j.code !== 200) return { ok: false, error: j.message || res.response };
			} catch (e) {}
		}
		return res;
	}

	if (ch_name === 'serverchan') {
		let key = trim('' + (ch_cfg.sendkey || ''));
		if (!key) return { ok: false, error: 'Server酱 SendKey 未填写' };
		let url = sprintf('https://sctapi.ftqq.com/%s.send', key);
		return http_request('POST', url, {
			title: sprintf('%s - %s', title, msg.number),
			desp: sprintf("**来信号码**: %s  \n**接收时间**: %s  \n**设备节点**: %s  \n\n**短信内容**:\n> %s",
				msg.number, msg.timestamp, msg.device, msg.text)
		});
	}

	if (ch_name === 'wecom') {
		let url = trim('' + (ch_cfg.webhook_url || ''));
		if (!url) return { ok: false, error: '企业微信 Webhook 地址未填写' };
		return http_request('POST', url, {
			msgtype: 'text',
			text: { content: body_full }
		});
	}

	if (ch_name === 'dingtalk') {
		let url = trim('' + (ch_cfg.webhook_url || ''));
		if (!url) return { ok: false, error: '钉钉 Webhook 地址未填写' };
		return http_request('POST', url, {
			msgtype: 'text',
			text: { content: body_full }
		});
	}

	if (ch_name === 'feishu') {
		let url = trim('' + (ch_cfg.webhook_url || ''));
		if (!url) return { ok: false, error: '飞书 Webhook 地址未填写' };
		return http_request('POST', url, {
			msg_type: 'text',
			content: { text: body_full }
		});
	}

	if (ch_name === 'webhook') {
		let url = trim('' + (ch_cfg.url || ''));
		let method = to_upper(trim('' + (ch_cfg.method || 'POST')));
		if (!url) return { ok: false, error: '自定义 Webhook URL 未填写' };
		url = replace(url, /\{number\}/g, url_encode(msg.number));
		url = replace(url, /\{text\}/g, url_encode(msg.text));
		url = replace(url, /\{time\}/g, url_encode(msg.timestamp));
		url = replace(url, /\{device\}/g, url_encode(msg.device));
		if (method === 'GET') {
			return http_request('GET', url, null);
		}
		return http_request('POST', url, {
			event: msg.event_type || 'sms',
			device: msg.device,
			modem_id: msg.modem_id || '0',
			number: msg.number,
			text: msg.text,
			timestamp: msg.timestamp
		});
	}

	return { ok: false, error: '未知渠道: ' + ch_name };
}

function dispatch_message(cfg, msg, only_channel) {
	let results = [];
	let any_ok = false;
	let order = [ 'telegram', 'bark', 'serverchan', 'wecom', 'dingtalk', 'feishu', 'webhook' ];
	let label_map = {
		telegram: 'Telegram',
		bark: 'Bark',
		serverchan: 'Server酱',
		wecom: '企业微信',
		dingtalk: '钉钉',
		feishu: '飞书',
		webhook: '自定义Webhook'
	};

	for (let ch in order) {
		if (only_channel && only_channel !== '' && only_channel !== 'all' && only_channel !== ch) continue;
		let ch_cfg = cfg.channels[ch];
		if (!ch_cfg) continue;
		if (!only_channel || only_channel === 'all') {
			if (!ch_cfg.enabled) continue;
		}
		let r = send_to_channel(ch, ch_cfg, msg);
		if (r.ok) {
			any_ok = true;
			append_log('INFO', sprintf('[%s] 转发成功 -> 号码:%s', label_map[ch] || ch, msg.number));
		} else {
			append_log('ERROR', sprintf('[%s] 转发失败 -> %s', label_map[ch] || ch, r.error || '未知错误'));
		}
		push(results, {
			channel: ch,
			label: label_map[ch] || ch,
			ok: r.ok,
			error: r.error || '',
			response: r.response || ''
		});
	}
	return { any_ok: any_ok, results: results };
}

function list_modem_ids() {
	let res = run_cmd_stdout('mmcli -L');
	let ids = [];
	let seen = {};
	if (res.output) {
		for (let line in split(res.output, '\n')) {
			let m = match(line, /\/Modem\/([0-9]+)/);
			if (m && !seen[m[1]]) {
				seen[m[1]] = true;
				push(ids, m[1]);
			}
		}
	}
	return ids;
}

function list_sms_ids_for_modem(mid) {
	let ids = [];
	let seen = {};
	let jres = run_mmcli_json('-m ' + shell_quote(mid) + ' --messaging-list-sms');
	if (jres) {
		let arr = jres['modem.messaging.sms'] || (jres.modem && jres.modem.messaging && jres.modem.messaging.sms);
		if (type(arr) === 'array') {
			for (let p in arr) {
				let m = match('' + p, /\/([0-9]+)$/);
				if (m && !seen[m[1]]) {
					seen[m[1]] = true;
					push(ids, m[1]);
				}
			}
		}
	}
	let tres = run_cmd('mmcli -m ' + shell_quote(mid) + ' --messaging-list-sms');
	if (tres.output) {
		for (let line in split(tres.output, '\n')) {
			let m = match(line, /\/SMS\/([0-9]+)/);
			if (m && !seen[m[1]]) {
				seen[m[1]] = true;
				push(ids, m[1]);
			}
		}
	}
	return ids;
}

function read_single_sms(sid) {
	let sj = run_mmcli_json('-s ' + shell_quote(sid));
	if (sj && sj.sms) {
		let p = sj.sms.properties || {};
		let c = sj.sms.content || {};
		return {
			state: to_lower('' + val_or(p.state, 'unknown')),
			pdu_type: to_lower('' + val_or(p['pdu-type'], '')),
			storage: '' + val_or(p.storage, 'mbim'),
			smsc: '' + val_or(p.smsc, '--'),
			number: '' + val_or(c.number, '未知号码'),
			text: normalize_sms_text(c.text, c.data),
			raw_ts: '' + val_or(p.timestamp, ''),
			timestamp: format_timestamp(p.timestamp)
		};
	}
	let kv = run_mmcli_kv('-s ' + shell_quote(sid));
	if (length(keys(kv)) > 0) {
		return {
			state: to_lower('' + val_or(kv['sms.properties.state'], 'unknown')),
			pdu_type: to_lower('' + val_or(kv['sms.properties.pdu-type'], '')),
			storage: '' + val_or(kv['sms.properties.storage'], 'mbim'),
			smsc: '' + val_or(kv['sms.properties.smsc'], '--'),
			number: '' + val_or(kv['sms.content.number'], '未知号码'),
			text: normalize_sms_text(kv['sms.content.text'], kv['sms.content.data']),
			raw_ts: '' + val_or(kv['sms.properties.timestamp'], ''),
			timestamp: format_timestamp(kv['sms.properties.timestamp'])
		};
	}
	return null;
}

function is_incoming_sms(info) {
	if (!info) return false;
	if (info.state === 'receiving' || info.state === 'sent' || info.state === 'sending') return false;
	if (info.state === 'received') return true;
	if (info.pdu_type === 'deliver') return true;
	return false;
}

// ============================================================================
// Sync SMS & Calls from Modem -> Local Database, and purge Modem storage!
// ============================================================================
function sync_modems_to_db(dry_init_only) {
	if (!acquire_file_lock(DB_LOCK_FILE, 15)) return;
	try {
		let modems = list_modem_ids();
		let sms_db = load_sms_db();
		let call_db = load_call_db();
		let sms_changed = false;
		let call_changed = false;
		let first_sms_init = !sms_db.initialized;
		let first_call_init = !call_db.initialized;
		let migrated_count = 0;

		for (let mid in modems) {
			// 1. Ingest all completed SMS from modem into local database and delete from modem
			let sms_ids = list_sms_ids_for_modem(mid);
			for (let sid in sms_ids) {
				let info = read_single_sms(sid);
				if (!info) continue;
				// Wait if multipart SMS is still receiving fragments or currently sending
				if (info.state === 'receiving' || info.state === 'sending') continue;

				let fp1 = make_sms_fp(info.number, info.timestamp, info.text);
				let fp2 = make_sms_fp(info.number, info.raw_ts, info.text);

				// Always delete from modem hardware first
				run_cmd_stdout('mmcli -m ' + shell_quote(mid) + ' --messaging-delete-sms=' + shell_quote(sid));

				// If this exact message was already ingested before (e.g. before reboot or ModemManager restart), skip!
				if (sms_db.seen_fp[fp1] || (info.raw_ts && sms_db.seen_fp[fp2])) {
					continue;
				}

				sms_db.seen_fp[fp1] = true;
				if (info.raw_ts) sms_db.seen_fp[fp2] = true;

				let incoming = is_incoming_sms(info);
				let mark_fwd = (dry_init_only || first_sms_init || !incoming) ? true : false;

				let db_id = '' + (sms_db.next_id++);
				let new_entry = {
					id: db_id,
					modem_id: '' + mid,
					number: info.number,
					text: info.text,
					state: incoming ? 'received' : info.state,
					storage: 'db',
					timestamp: info.timestamp,
					forwarded: mark_fwd
				};
				push(sms_db.messages, new_entry);
				sms_changed = true;
				migrated_count++;
			}

			// 2. Sync voice calls from modem into local database and delete terminated calls from modem
			let cres = run_cmd_stdout('mmcli -m ' + shell_quote(mid) + ' --voice-list-calls');
			if (cres.output) {
				for (let line in split(cres.output, '\n')) {
					let m = match(line, /\/Call\/([0-9]+)/);
					if (!m) continue;
					let cid = m[1];
					let cj = run_mmcli_json('-o ' + shell_quote(cid));
					let cp = (cj && cj.call && cj.call.properties) ? cj.call.properties : null;
					if (!cp) {
						let kv = run_mmcli_kv('-o ' + shell_quote(cid));
						if (length(keys(kv)) > 0) {
							cp = {
								number: kv['call.properties.number'],
								direction: kv['call.properties.direction'],
								state: kv['call.properties.state'],
								'state-reason': kv['call.properties.state-reason'],
								multiparty: kv['call.properties.multiparty'],
								'audio-port': kv['call.properties.audio-port']
							};
						}
					}
					if (!cp) continue;

					let cnum = '' + val_or(cp.number, '未知号码');
					let cdir = to_lower('' + val_or(cp.direction, 'unknown'));
					let cst = to_lower('' + val_or(cp.state, 'unknown'));
					let creason = '' + val_or(cp['state-reason'], '--');

					// Check if an active (non-terminated) record in call_db matches this modem & orig_id
					let existing_call = null;
					for (let c_item in call_db.calls) {
						if (c_item.modem_id === ('' + mid) && c_item.orig_id === ('' + cid) && c_item.active_on_modem) {
							existing_call = c_item;
							break;
						}
					}

					if (existing_call) {
						if (existing_call.state !== cst || existing_call.state_reason !== creason || existing_call.number !== cnum) {
							existing_call.state = cst;
							existing_call.state_reason = creason;
							existing_call.number = cnum;
							call_changed = true;
						}
						if (cst === 'terminated') {
							existing_call.active_on_modem = false;
							call_changed = true;
							run_cmd_stdout('mmcli -m ' + shell_quote(mid) + ' --voice-delete-call=' + shell_quote(cid));
						}
					} else {
						let call_db_id = '' + (call_db.next_id++);
						let mark_call_fwd = (dry_init_only || first_call_init || cdir !== 'incoming') ? true : false;
						let new_call = {
							id: call_db_id,
							modem_id: '' + mid,
							orig_id: '' + cid,
							path: '/local/db/Call/' + call_db_id,
							number: cnum,
							direction: cdir,
							state: cst,
							state_reason: creason,
							multiparty: '' + val_or(cp.multiparty, 'no'),
							audio_port: '' + val_or(cp['audio-port'], '--'),
							timestamp: now_str(),
							active_on_modem: (cst !== 'terminated'),
							forwarded: mark_call_fwd
						};
						push(call_db.calls, new_call);
						call_changed = true;
						if (cst === 'terminated') {
							run_cmd_stdout('mmcli -m ' + shell_quote(mid) + ' --voice-delete-call=' + shell_quote(cid));
						}
					}
				}
			}
		}

		if (!sms_db.initialized) {
			sms_db.initialized = true;
			sms_changed = true;
			if (migrated_count > 0) {
				append_log('INFO', sprintf('已将模块存量短信 (%d 条) 转存至路由器本地数据库并清空模块存储', migrated_count));
			}
		}
		if (!call_db.initialized) {
			call_db.initialized = true;
			call_changed = true;
		}

		if (sms_changed) {
			sort(sms_db.messages, function(a, b) { return int(b.id) - int(a.id); });
			save_sms_db(sms_db);
		}
		if (call_changed) {
			sort(call_db.calls, function(a, b) { return int(b.id) - int(a.id); });
			save_call_db(call_db);
		}
	} catch (err) {
		append_log('ERROR', '同步模块数据至本地数据库异常: ' + err);
	}
	release_file_lock(DB_LOCK_FILE);
}

function forward_pending_from_db(cfg) {
	if (!cfg.enabled) return;

	// 1. Forward any unforwarded incoming SMS in local DB
	let sms_db = load_sms_db();
	let sms_modified = false;
	let to_delete_ids = {};

	// Iterate oldest to newest so notifications arrive in chronological order
	let total = length(sms_db.messages);
	for (let i = total - 1; i >= 0; i--) {
		let m = sms_db.messages[i];
		if (!m || m.forwarded) continue;
		if (m.state !== 'received' && m.pdu_type !== 'deliver') {
			m.forwarded = true;
			sms_modified = true;
			continue;
		}

		append_log('INFO', sprintf('本地数据库已入库新短信 #%s (来自: %s，模块存储已释放)，正在自动推送...', m.id, m.number));
		let msg = {
			event_type: 'sms',
			event_title: '收到新短信',
			device: cfg.device_tag || get_hostname(),
			modem_id: m.modem_id || '0',
			number: m.number || '未知号码',
			text: (m.text && m.text !== '') ? m.text : '(空短信内容)',
			timestamp: m.timestamp || now_str()
		};

		m.forwarded = true;
		save_sms_db(sms_db);
		let disp = dispatch_message(cfg, msg, null);
		if (disp.any_ok) {
			sms_modified = true;
			if (cfg.delete_after_forward) {
				to_delete_ids[m.id] = true;
				append_log('INFO', sprintf('已按配置在转发成功后清理本地数据库短信记录 #%s', m.id));
			}
		} else if (length(disp.results) === 0) {
			append_log('WARN', sprintf('新短信 #%s 已存入本地数据库，但当前未勾选任何转发渠道（如 Telegram / Bark）！', m.id));
		}
	}

	if (length(keys(to_delete_ids)) > 0) {
		let kept = [];
		for (let item in sms_db.messages) {
			if (!to_delete_ids[item.id]) {
				push(kept, item);
			} else if (type(sms_db.seen_fp) === 'object') {
				delete sms_db.seen_fp[make_sms_fp(item.number, item.timestamp, item.text)];
			}
		}
		sms_db.messages = kept;
		sms_modified = true;
	}
	if (sms_modified) {
		save_sms_db(sms_db);
	}

	// 2. Forward any unforwarded incoming calls if enabled
	if (cfg.forward_calls) {
		let call_db = load_call_db();
		let call_modified = false;
		for (let c in call_db.calls) {
			if (!c || c.forwarded) continue;
			if (c.direction !== 'incoming') {
				c.forwarded = true;
				call_modified = true;
				continue;
			}
			let cmsg = {
				event_type: 'call',
				event_title: '来电提醒',
				device: cfg.device_tag || get_hostname(),
				modem_id: c.modem_id || '0',
				number: c.number || '未知号码',
				text: sprintf('有新的呼入来电 (当前状态: %s)', c.state || 'incoming'),
				timestamp: c.timestamp || now_str()
			};
			let cdisp = dispatch_message(cfg, cmsg, null);
			if (cdisp.any_ok) {
				c.forwarded = true;
				call_modified = true;
			}
		}
		if (call_modified) {
			save_call_db(call_db);
		}
	}
}

let mode = ARGV[0] || '--help';

if (mode === '--status') {
	let cfg = load_config();
	let running = ensure_monitor_running();
	let logs = trim(readfile(LOG_FILE) || '');
	print(sprintf('%J\n', {
		code: 0,
		running: running,
		config: cfg,
		logs: logs
	}));
	exit(0);
}

if (mode === '--save') {
	let raw_json = ARGV[1] || '';
	if (raw_json !== '') {
		try {
			let parsed = json(raw_json);
			if (type(parsed) === 'object') {
				writefile(CONFIG_FILE, sprintf('%J\n', parsed));
			}
		} catch (e) {}
	}
	let cfg = load_config();
	let ch_names = enabled_channel_names(cfg);
	sync_modems_to_db(false);
	if (cfg.enabled) {
		if (length(ch_names) > 0) {
			append_log('INFO', sprintf('已保存并启用自动转发 (已启用渠道: %s)', join('、', ch_names)));
		} else {
			append_log('WARN', '已开启自动转发总开关，但尚未勾选任何推送渠道（请勾选 Telegram 或 Bark 等渠道）');
		}
	} else {
		append_log('INFO', '已保存配置（自动转发总开关当前为关闭状态）');
	}
	let running = ensure_monitor_running();
	print(sprintf('%J\n', {
		code: 0,
		running: running,
		message: cfg.enabled
			? (length(ch_names) > 0
				? ('配置已保存！已启用 [' + join('、', ch_names) + '] 自动转发')
				: '配置已保存（注意：您尚未勾选任何具体推送渠道！）')
			: '配置已保存（自动转发已关闭）'
	}));
	exit(0);
}

if (mode === '--clear-logs') {
	writefile(LOG_FILE, '');
	print(sprintf('%J\n', { code: 0, message: '转发日志已清空' }));
	exit(0);
}

if (mode === '--init-seen') {
	sync_modems_to_db(true);
	let sms_db = load_sms_db();
	let changed = false;
	for (let m in sms_db.messages) {
		if (m && !m.forwarded) {
			m.forwarded = true;
			changed = true;
		}
	}
	if (changed) save_sms_db(sms_db);
	print('OK\n');
	exit(0);
}

if (mode === '--test') {
	let target_ch = ARGV[1] || 'all';
	let raw_json = ARGV[2] || '';
	if (raw_json !== '') {
		try {
			let parsed = json(raw_json);
			if (type(parsed) === 'object') {
				writefile(CONFIG_FILE, sprintf('%J\n', parsed));
			}
		} catch (e) {}
	}
	let cfg = load_config();
	ensure_monitor_running();
	let test_msg = {
		event_type: 'test',
		event_title: '短信转发测试消息',
		device: cfg.device_tag || get_hostname(),
		modem_id: '0',
		number: '10010',
		text: '这是一条来自 OpenWrt ModemManager 管理中心的测试通知，说明您的推送通道已配置成功！',
		timestamp: now_str()
	};
	let disp = dispatch_message(cfg, test_msg, target_ch);
	if (disp.any_ok) {
		let cfg_modified = false;
		if (target_ch !== 'all' && cfg.channels && type(cfg.channels[target_ch]) === 'object' && !cfg.channels[target_ch].enabled) {
			cfg.channels[target_ch].enabled = true;
			cfg_modified = true;
		}
		if (!cfg.enabled) {
			cfg.enabled = true;
			cfg_modified = true;
		}
		if (cfg_modified) {
			writefile(CONFIG_FILE, sprintf('%J\n', cfg));
		}
	}
	print(sprintf('%J\n', disp));
	exit(0);
}

if (mode === '--forward-latest') {
	let raw_json = ARGV[1] || '';
	if (raw_json !== '') {
		try {
			let parsed = json(raw_json);
			if (type(parsed) === 'object') {
				writefile(CONFIG_FILE, sprintf('%J\n', parsed));
			}
		} catch (e) {}
	}
	let cfg = load_config();
	ensure_monitor_running();
	sync_modems_to_db(false);
	let sms_db = load_sms_db();
	if (length(sms_db.messages) === 0) {
		print(sprintf('%J\n', { any_ok: false, error: '当前本地数据库中没有可转发的短信记录', results: [] }));
		exit(0);
	}
	let latest = sms_db.messages[0];
	append_log('INFO', sprintf('手动触发真实短信转发: #%s (来自: %s)', latest.id, latest.number));
	let real_msg = {
		event_type: 'sms',
		event_title: '收到新短信 (真实短信推送)',
		device: cfg.device_tag || get_hostname(),
		modem_id: latest.modem_id || '0',
		number: latest.number,
		text: latest.text !== '' ? latest.text : '(空短信内容)',
		timestamp: latest.timestamp
	};
	let disp = dispatch_message(cfg, real_msg, 'all');
	print(sprintf('%J\n', disp));
	exit(0);
}

if (mode === '--once') {
	if (!acquire_file_lock(LOCK_FILE, 20)) exit(0);
	try {
		sync_modems_to_db(false);
		let cfg = load_config();
		if (cfg.enabled) {
			forward_pending_from_db(cfg);
		}
	} catch (err) {
		append_log('ERROR', '自动转存与转发扫描异常: ' + err);
	}
	release_file_lock(LOCK_FILE);
	exit(0);
}

if (mode === '--sync-db') {
	sync_modems_to_db(false);
	let cfg = load_config();
	if (cfg.enabled) {
		forward_pending_from_db(cfg);
	}
	let sms_db = load_sms_db();
	let call_db = load_call_db();
	print(sprintf('%J\n', {
		code: 0,
		sms_count: length(sms_db.messages),
		messages: sms_db.messages,
		call_count: length(call_db.calls),
		calls: call_db.calls
	}));
	exit(0);
}

if (mode === '--daemon') {
	append_log('INFO', 'ModemManager 短信数据库转存与自动转发守护进程已启动');
	while (true) {
		try {
			sync_modems_to_db(false);
			let cfg = load_config();
			if (cfg.enabled) {
				forward_pending_from_db(cfg);
			}
		} catch (err) {
			append_log('ERROR', '守护进程扫描异常: ' + err);
		}
		let cfg2 = load_config();
		let iv = int(cfg2.poll_interval) || 5;
		if (iv < 2) iv = 2;
		if (iv > 60) iv = 60;
		run_cmd_stdout('sleep ' + iv);
	}
}
EOF_FWD_BIN

	cat > "$TARGET_DIR/htdocs/luci-static/resources/view/modemmanager/index.js" <<'EOF_VIEW_JS'
'use strict';
'require view';
'require dom';
'require poll';
'require rpc';
'require fs';
'require ui';

var callGetStatus = rpc.declare({
	object: 'luci.modemmanager',
	method: 'get_status',
	params: [ 'modem' ],
	expect: { '': {} }
});

var callListSms = rpc.declare({
	object: 'luci.modemmanager',
	method: 'list_sms',
	params: [ 'modem' ],
	expect: { '': {} }
});

var callDeleteSms = rpc.declare({
	object: 'luci.modemmanager',
	method: 'delete_sms',
	params: [ 'modem', 'id' ],
	expect: { '': {} }
});

var callDeleteAllSms = rpc.declare({
	object: 'luci.modemmanager',
	method: 'delete_all_sms',
	params: [ 'modem' ],
	expect: { '': {} }
});

var callSendSms = rpc.declare({
	object: 'luci.modemmanager',
	method: 'send_sms',
	params: [ 'modem', 'number', 'text' ],
	expect: { '': {} }
});

var callListCalls = rpc.declare({
	object: 'luci.modemmanager',
	method: 'list_calls',
	params: [ 'modem' ],
	expect: { '': {} }
});

var callDeleteCall = rpc.declare({
	object: 'luci.modemmanager',
	method: 'delete_call',
	params: [ 'modem', 'id' ],
	expect: { '': {} }
});

var callDeleteAllCalls = rpc.declare({
	object: 'luci.modemmanager',
	method: 'delete_all_calls',
	params: [ 'modem' ],
	expect: { '': {} }
});

var callCreateCall = rpc.declare({
	object: 'luci.modemmanager',
	method: 'create_call',
	params: [ 'modem', 'number' ],
	expect: { '': {} }
});

var callCallAction = rpc.declare({
	object: 'luci.modemmanager',
	method: 'call_action',
	params: [ 'modem', 'id', 'action' ],
	expect: { '': {} }
});

var callModemAction = rpc.declare({
	object: 'luci.modemmanager',
	method: 'modem_action',
	params: [ 'modem', 'action' ],
	expect: { '': {} }
});

var callUssdQuery = rpc.declare({
	object: 'luci.modemmanager',
	method: 'ussd_query',
	params: [ 'modem', 'code', 'action' ],
	expect: { '': {} }
});

var callGetForwardConfig = rpc.declare({
	object: 'luci.modemmanager',
	method: 'get_forward_config',
	params: [],
	expect: { '': {} }
});

var callSaveForwardConfig = rpc.declare({
	object: 'luci.modemmanager',
	method: 'save_forward_config',
	params: [ 'config' ],
	expect: { '': {} }
});

var callTestForward = rpc.declare({
	object: 'luci.modemmanager',
	method: 'test_forward',
	params: [ 'channel', 'config' ],
	expect: { '': {} }
});

var callGetForwardLogs = rpc.declare({
	object: 'luci.modemmanager',
	method: 'get_forward_logs',
	params: [],
	expect: { '': {} }
});

var callClearForwardLogs = rpc.declare({
	object: 'luci.modemmanager',
	method: 'clear_forward_logs',
	params: [],
	expect: { '': {} }
});

var callForwardLatest = rpc.declare({
	object: 'luci.modemmanager',
	method: 'forward_latest',
	params: [ 'config' ],
	expect: { '': {} }
});

var callGetAtPresets = rpc.declare({
	object: 'luci.modemmanager',
	method: 'get_at_presets',
	params: [],
	expect: { '': {} }
});

var callSaveAtPresets = rpc.declare({
	object: 'luci.modemmanager',
	method: 'save_at_presets',
	params: [ 'presets' ],
	expect: { '': {} }
});

var callSendAt = rpc.declare({
	object: 'luci.modemmanager',
	method: 'send_at',
	params: [ 'modem', 'command' ],
	expect: { '': {} }
});

var callEnableAtDebug = rpc.declare({
	object: 'luci.modemmanager',
	method: 'enable_at_debug',
	params: [],
	expect: { '': {} }
});

function defaultForwardConfig() {
	return {
		enabled: false,
		poll_interval: 5,
		device_tag: 'OpenWrt',
		forward_calls: false,
		delete_after_forward: false,
		channels: {
			telegram: { enabled: false, bot_token: '', chat_id: '', api_host: 'https://api.telegram.org' },
			bark: { enabled: false, server_url: 'https://api.day.app', device_key: '', group: 'OpenWrt短信', sound: '' },
			serverchan: { enabled: false, sendkey: '' },
			wecom: { enabled: false, webhook_url: '' },
			dingtalk: { enabled: false, webhook_url: '' },
			feishu: { enabled: false, webhook_url: '' },
			webhook: { enabled: false, url: '', method: 'POST' }
		}
	};
}

var CN_PLMN_MAP = {
	'46000': '中国移动 (CMCC)',
	'46002': '中国移动 (CMCC)',
	'46004': '中国移动 (CMCC)',
	'46007': '中国移动 (CMCC)',
	'46008': '中国移动 (CMCC)',
	'46001': '中国联通 (CUCC)',
	'46006': '中国联通 (CUCC)',
	'46009': '中国联通 (CUCC)',
	'46003': '中国电信 (CTCC)',
	'46005': '中国电信 (CTCC)',
	'46011': '中国电信 (CTCC)',
	'46015': '中国广电 (CBN)',
	'46020': '中国铁通 (CRTC)'
};

var SMS_STORAGE_CN = {
	'db': '本地数据库 (已释放模块)',
	'sm': 'SIM卡存储 (sm)',
	'me': '模块闪存 (me)',
	'mt': 'SIM+模块混合存储 (mt)',
	'sr': '状态报告存储 (sr)',
	'bm': '小区广播存储 (bm)',
	'ta': '终端适配存储 (ta)',
	'mbim': 'MBIM 统一存储',
	'unknown': 'MBIM 统一存储'
};

var CALL_REASON_CN = {
	'outgoing-started': '主叫拨号发起',
	'incoming-new': '新来电呼入',
	'terminated': '正常通话挂断',
	'transferred': '呼叫已转移',
	'deflected': '呼叫已偏转',
	'refused-or-busy': '对方拒接或忙线',
	'refused': '对方拒接',
	'error': '通话异常中断',
	'audio-setup-failed': '音频通道建立失败',
	'network-problem': '移动网络故障'
};

var REG_STATE_CN = {
	'home': '本地网络 (Home)',
	'roaming': '漫游网络 (Roaming)',
	'searching': '正在搜网 (Searching)',
	'denied': '注册被拒 (Denied)',
	'idle': '空闲未注册 (Idle)',
	'unknown': '未知状态'
};

var MODEM_STATE_SHORT_CN = {
	'connected': '已连接',
	'registered': '已注册',
	'connecting': '连接中',
	'searching': '搜网中',
	'enabled': '已启用',
	'locked': '已锁定',
	'failed': '模块异常',
	'disabled': '已禁用',
	'initializing': '初始化中'
};

var DEFAULT_AT_PRESETS = [
	{ cmd: 'ATI', desc: '查询模块厂商与型号信息 (ATI)' },
	{ cmd: 'AT+CGMR', desc: '查询模块固件版本 (AT+CGMR)' },
	{ cmd: 'AT+CGSN', desc: '查询模块 IMEI 串号 (AT+CGSN)' },
	{ cmd: 'AT+CSQ', desc: '查询 2G/3G/4G 信号强度 (AT+CSQ)' },
	{ cmd: 'AT+CESQ', desc: '查询扩展信号质量 RSRP/RSRQ/SINR (AT+CESQ)' },
	{ cmd: 'AT+CPIN?', desc: '查询 SIM 卡在位与 PIN 状态 (AT+CPIN?)' },
	{ cmd: 'AT+CIMI', desc: '查询 SIM 卡 IMSI 识别码 (AT+CIMI)' },
	{ cmd: 'AT+CCID', desc: '查询 SIM 卡 ICCID 卡号 (AT+CCID)' },
	{ cmd: 'AT+CNUM', desc: '查询 SIM 卡本机号码 (AT+CNUM)' },
	{ cmd: 'AT+COPS?', desc: '查询当前注册运营商与网络制式 (AT+COPS?)' },
	{ cmd: 'AT+C5GREG?', desc: '查询 5G NR 网络注册状态 (AT+C5GREG?)' },
	{ cmd: 'AT+CGDCONT?', desc: '查询 APN PDP 上下文配置 (AT+CGDCONT?)' },
	{ cmd: 'AT+CGPADDR', desc: '查询当前分配的 PDP IP 地址 (AT+CGPADDR)' },
	{ cmd: 'AT+GTCCINFO?', desc: '广和通 Fibocom 查询服务小区与邻区详情 (AT+GTCCINFO?)' },
	{ cmd: 'AT+GTRAT?', desc: '广和通 Fibocom 查询当前网络制式配置 (AT+GTRAT?)' },
	{ cmd: 'AT+GTUSBMODE?', desc: '广和通 Fibocom 查询当前 USB 网卡工作模式 (AT+GTUSBMODE?)' },
	{ cmd: 'AT+CPMS?', desc: '查询短信存储区容量与偏好 (AT+CPMS?)' },
	{ cmd: 'AT+CFUN=1,1', desc: '软重启蜂窝模块 (AT+CFUN=1,1)' }
];

var LS_CALL_META_KEY = 'luci_modemmanager_call_timestamps_v1';

function ensureMmThemeStyles() {
	if (typeof document === 'undefined') return;
	try { window.localStorage.removeItem('luci_modemmanager_theme_mode_v1'); } catch (e) {}
	if (document.documentElement) {
		document.documentElement.classList.remove('mm-dark-mode');
		[
			'--mm-card-bg', '--mm-subcard-bg', '--mm-border', '--mm-border-subtle',
			'--mm-text-primary', '--mm-text-secondary', '--mm-accent', '--mm-bar-track',
			'--mm-input-bg', '--mm-input-border', '--mm-shadow'
		].forEach(function(prop) {
			document.documentElement.style.removeProperty(prop);
		});
	}
	var styleEl = document.getElementById('mm-theme-styles');
	if (!styleEl) {
		styleEl = document.createElement('style');
		styleEl.id = 'mm-theme-styles';
		document.head.appendChild(styleEl);
	}
	styleEl.textContent = [
		':root {',
		'  --mm-card-bg: var(--background-color-high, rgba(128, 128, 128, 0.05));',
		'  --mm-subcard-bg: var(--background-color-medium, rgba(128, 128, 128, 0.08));',
		'  --mm-border: var(--border-color-medium, rgba(128, 128, 128, 0.24));',
		'  --mm-border-subtle: var(--border-color-low, rgba(128, 128, 128, 0.16));',
		'  --mm-text-primary: var(--text-color-high, inherit);',
		'  --mm-text-secondary: var(--text-color-medium, rgba(128, 128, 128, 0.88));',
		'  --mm-accent: var(--primary-color-high, #0969da);',
		'  --mm-bar-track: rgba(128, 128, 128, 0.25);',
		'  --mm-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);',
		'}'
	].join('\n');
}

function valOr(v, fb) {
	if (v === null || v === undefined || v === '' || v === '--' || v === 'unknown') return fb;
	return v;
}

// Strip timezone suffixes such as +08, +08:00, +0800, or Z
function cleanTimestamp(ts) {
	if (!ts || ts === '--' || ts === 'unknown') return '--';
	var s = ('' + ts).trim();
	var m = s.match(/^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})/);
	if (m) return m[1] + ' ' + m[2];
	return s.replace('T', ' ').replace(/\s*\(?([+-]\d{2}(:?\d{2})?|Z)\)?$/, '').trim();
}

function nowFormatted() {
	var d = new Date();
	var pad = function(n) { return n < 10 ? ('0' + n) : ('' + n); };
	return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
		pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds());
}

function getLocalCallTimestamp(modemId, callId, number, backendTs) {
	if (backendTs && backendTs !== '--' && backendTs !== 'unknown') {
		return cleanTimestamp(backendTs);
	}
	var store = {};
	try {
		var raw = window.localStorage.getItem(LS_CALL_META_KEY);
		if (raw) store = JSON.parse(raw) || {};
	} catch (e) { store = {}; }

	var key = modemId + ':' + callId + ':' + (number || '');
	if (!store[key] || store[key] === '--') {
		store[key] = nowFormatted();
		try {
			window.localStorage.setItem(LS_CALL_META_KEY, JSON.stringify(store));
		} catch (e) {}
	}
	return cleanTimestamp(store[key]);
}

function removeLocalCallTimestamp(modemId, callId) {
	try {
		var raw = window.localStorage.getItem(LS_CALL_META_KEY);
		if (!raw) return;
		var store = JSON.parse(raw) || {};
		var prefix = modemId + ':' + callId + ':';
		Object.keys(store).forEach(function(k) {
			if (k.indexOf(prefix) === 0) delete store[k];
		});
		window.localStorage.setItem(LS_CALL_META_KEY, JSON.stringify(store));
	} catch (e) {}
}

function dedupModelName(man, mod) {
	var m1 = (man || '').trim();
	var m2 = (mod || '').trim();
	if (m1 && m2 && m2.toLowerCase().indexOf(m1.toLowerCase() + ' ') === 0) {
		m2 = m2.substring(m1.length).trim();
	}
	return m2 || m1;
}

function formatOperatorCn(name, code) {
	var c = valOr(code, '');
	var n = valOr(name, '');
	if (c && CN_PLMN_MAP[c]) return CN_PLMN_MAP[c];
	var up = n.toUpperCase();
	if (up === 'CMCC' || up === 'CHINA MOBILE' || up === 'CHN-CMCC') return '中国移动 (CMCC)';
	if (up === 'CHN-UNICOM' || up === 'CUCC' || up === 'CHINA UNICOM' || up === 'UNICOM') return '中国联通 (CUCC)';
	if (up === 'CHN-CT' || up === 'CTCC' || up === 'CHINA TELECOM') return '中国电信 (CTCC)';
	if (up === 'CBN' || up === 'CHINA BROADNET') return '中国广电 (CBN)';
	return n || c || '--';
}

function formatModemOptionText(m, activeModemId, activeStatus) {
	var name = m.name || ('模块 #' + m.id);
	var op = valOr(m.operator, '');
	var st = valOr(m.state, '');
	if (!op && activeStatus && ('' + m.id) === ('' + activeModemId)) {
		op = valOr(activeStatus.operator_name, '');
		if (!st) st = valOr(activeStatus.state, '');
	}
	var badge = op || (st ? (MODEM_STATE_SHORT_CN[st.toLowerCase()] || st) : '');
	if (badge && badge !== '--' && badge.toLowerCase() !== 'unknown') {
		return name + ' [' + badge + ']';
	}
	return name;
}

function decodeUcs2HexJs(hexStr) {
	if (!hexStr) return null;
	var clean = ('' + hexStr).replace(/\s+/g, '');
	if (clean.length < 4 || (clean.length % 4) !== 0 || !/^[0-9a-fA-F]+$/.test(clean)) return null;
	var out = '';
	for (var i = 0; i < clean.length; i += 4) {
		var code = parseInt(clean.substring(i, i + 4), 16);
		if (isNaN(code)) return null;
		if (code === 0) continue;
		out += String.fromCharCode(code);
	}
	return out;
}

function normalizeSmsTextJs(txtVal, dataVal) {
	var txt = (txtVal === null || txtVal === undefined || txtVal === '--') ? '' : ('' + txtVal);
	var dat = (dataVal === null || dataVal === undefined || dataVal === '--') ? '' : ('' + dataVal);
	if (txt && txt.length >= 8 && (txt.length % 4) === 0 && /^[0-9A-Fa-f]+$/.test(txt)) {
		if (/(00[2-7][0-9A-Fa-f]|[4-9][0-9A-Fa-f]{3}|30[0-9A-Fa-f]{2}|FF[0-9A-Fa-f]{2})/.test(txt)) {
			var dec = decodeUcs2HexJs(txt);
			if (dec) return dec;
		}
	}
	if (txt) return txt;
	if (dat) {
		var decData = decodeUcs2HexJs(dat);
		if (decData) return decData;
		return '[二进制数据 SMS: ' + dat + ']';
	}
	return '';
}

function parseKvOutput(stdout) {
	var kv = {};
	var lines = (stdout || '').split(/\r?\n/);
	for (var i = 0; i < lines.length; i++) {
		var m = lines[i].match(/^([^:]+)\s*:\s*(.*)$/);
		if (m) {
			var k = m[1].trim();
			var v = m[2].trim();
			if (v !== '' && v !== '--') kv[k] = v;
		}
	}
	return kv;
}

function runMmcliDirect(args) {
	return fs.exec('/usr/bin/mmcli', args).then(function(res) {
		return {
			code: res ? res.code : -1,
			stdout: (res && res.stdout) ? res.stdout.trim() : '',
			stderr: (res && res.stderr) ? res.stderr.trim() : ''
		};
	}).catch(function(err) {
		return { code: -1, stdout: '', stderr: '' + err };
	});
}

function runForwarderDirect(args) {
	return fs.exec('/usr/libexec/rpcd/luci.modemmanager', args).then(function(res) {
		if (res && res.stdout) {
			try {
				var j = JSON.parse(res.stdout.trim());
				if (j && typeof j === 'object' && !j.error) return j;
				if (j && typeof j === 'object' && Array.isArray(j.results)) return j;
			} catch (e) {}
		}
		return fs.exec('/usr/bin/modemmanager-sms-forwarder', args).then(function(res2) {
			if (res2 && res2.stdout) {
				try {
					var j2 = JSON.parse(res2.stdout.trim());
					if (j2 && typeof j2 === 'object') return j2;
				} catch (e2) {}
			}
			return { code: res2 ? res2.code : -1, error: (res2 && (res2.stderr || res2.stdout)) ? (res2.stderr || res2.stdout).trim() : '执行失败' };
		});
	}).catch(function(err) {
		return { code: -1, error: '' + err };
	});
}

function directGetMessagingStorage(modemId, primaryPort) {
	return runMmcliDirect([ '-m', '' + modemId, '--messaging-status', '-J' ]).then(function(res) {
		var defSt = '--';
		var supSt = '--';
		if (res.code === 0 && res.stdout) {
			try {
				var j = JSON.parse(res.stdout);
				var msg = (j && j.modem && j.modem.messaging) ? j.modem.messaging : {};
				defSt = valOr(msg['default-storage'], '--');
				if (Array.isArray(msg['supported-storages'])) {
					var valid = msg['supported-storages'].filter(function(s) { return s && s !== '--' && s !== 'unknown'; });
					if (valid.length > 0) supSt = valid.join(', ');
				}
			} catch (e) {}
		}
		if (defSt !== '--' && supSt !== '--') {
			return { default_storage: defSt, supported_storages: supSt };
		}
		return runMmcliDirect([ '-m', '' + modemId, '--messaging-status' ]).then(function(tres) {
			var out = tres.stdout || '';
			var mSup = out.match(/supported storages:\s*'?([^'\r\n]+)'?/i);
			var mDef = out.match(/default storage:\s*'?([^'\r\n]+)'?/i);
			if (mSup && supSt === '--') {
				var v1 = mSup[1].trim();
				if (v1 !== '--' && v1 !== 'unknown') supSt = v1;
			}
			if (mDef && defSt === '--') {
				var v2 = mDef[1].trim();
				if (v2 !== '--' && v2 !== 'unknown') defSt = v2;
			}
			if (defSt === '--' && primaryPort && primaryPort.indexOf('cdc-wdm') !== -1) {
				defSt = 'mbim';
				supSt = 'SIM卡 + 模块自动管理';
			}
			return { default_storage: defSt, supported_storages: supSt };
		});
	});
}

function directGetSignalAndBearer(modemId, bearerPaths) {
	var sigPromise = runMmcliDirect([ '-m', '' + modemId, '--signal-get', '-J' ]).then(function(sres) {
		if (sres.code === 0 && sres.stdout) {
			try {
				var sj = JSON.parse(sres.stdout);
				var sig = (sj && sj.modem && sj.modem.signal) ? sj.modem.signal : {};
				var nr = sig['5g'] || {};
				var lte = sig.lte || {};
				var rsrp = valOr(nr.rsrp, valOr(lte.rsrp, ''));
				var rsrq = valOr(nr.rsrq, valOr(lte.rsrq, ''));
				var snr = valOr(nr.snr, valOr(lte.snr, ''));
				var parts = [];
				if (rsrp) parts.push('RSRP: ' + rsrp + ' dBm');
				if (snr) parts.push('SINR: ' + snr + ' dB');
				if (rsrq) parts.push('RSRQ: ' + rsrq + ' dB');
				if (parts.length > 0) return parts.join(' | ');
			} catch (e) {}
		}
		runMmcliDirect([ '-m', '' + modemId, '--signal-setup=30' ]);
		return '';
	});

	var bearerPromise = Promise.resolve('--');
	if (Array.isArray(bearerPaths) && bearerPaths.length > 0) {
		var bm = ('' + bearerPaths[0]).match(/\/(\d+)$/);
		if (bm) {
			bearerPromise = runMmcliDirect([ '-b', bm[1], '-J' ]).then(function(bres) {
				if (bres.code === 0 && bres.stdout) {
					try {
						var bj = JSON.parse(bres.stdout);
						var b = (bj && bj.bearer) ? bj.bearer : {};
						var ipv4 = (b['ipv4-config'] && valOr(b['ipv4-config'].address, '')) || '';
						var ipv6 = (b['ipv6-config'] && valOr(b['ipv6-config'].address, '')) || '';
						var apn = (b.properties && valOr(b.properties.apn, '')) || '';
						var bparts = [];
						if (ipv4) bparts.push(ipv4);
						if (ipv6) bparts.push(ipv6);
						if (apn) bparts.push('APN: ' + apn);
						if (bparts.length > 0) return bparts.join(' / ');
					} catch (e) {}
				}
				return '--';
			});
		}
	}

	return Promise.all([ sigPromise, bearerPromise ]).then(function(r) {
		return { signal_ext: r[0], bearer_info: r[1] };
	});
}

function directGetStatus(reqModemId) {
	return runMmcliDirect([ '-L' ]).then(function(lres) {
		var lines = (lres.stdout || '').split(/\r?\n/);
		var modems = [];
		for (var i = 0; i < lines.length; i++) {
			var m = lines[i].match(/(\/org\/freedesktop\/ModemManager1\/Modem\/(\d+))\s*(?:\[([^\]]+)\])?\s*(.*)$/);
			if (m) {
				var id = m[2];
				var man = valOr(m[3], 'Modem');
				var mod = dedupModelName(man, valOr((m[4] || '').trim(), '#' + id));
				modems.push({
					id: id,
					path: m[1],
					name: (man + ' ' + mod).trim() + ' (模块 #' + id + ')',
					manufacturer: man,
					model: mod,
					state: '',
					operator: '--',
					number: '--'
				});
			}
		}

		if (modems.length === 0) {
			return {
				found: false,
				modems: [],
				error: lres.code !== 0
					? ('调用 mmcli 权限受限或未重登 LuCI 会话 (' + (lres.stderr || '请尝试重新登录 LuCI 或重启 rpcd') + ')')
					: '未检测到 ModemManager 管理的调制解调器 (mmcli -L 输出为空)'
			};
		}

		var targetId = modems[0].id;
		var targetIndex = 0;
		for (var j = 0; j < modems.length; j++) {
			if (modems[j].id === ('' + reqModemId)) {
				targetId = modems[j].id;
				targetIndex = j;
				break;
			}
		}

		return runMmcliDirect([ '-m', targetId, '-J' ]).then(function(jres) {
			var parsed = null;
			if (jres.code === 0 && jres.stdout) {
				try { parsed = JSON.parse(jres.stdout); } catch (e) { parsed = null; }
			}
			if (parsed && parsed.modem) {
				var md = parsed.modem;
				var g = md.generic || {};
				var g3 = md['3gpp'] || {};
				var sigVal = (g['signal-quality'] && g['signal-quality'].value) ? parseInt(g['signal-quality'].value, 10) : 0;
				var ownNum = (Array.isArray(g['own-numbers']) && g['own-numbers'].length > 0) ? g['own-numbers'][0] : '--';
				var tech = Array.isArray(g['access-technologies']) ? g['access-technologies'].join(', ').toUpperCase() : '--';
				var opName = formatOperatorCn(g3['operator-name'], g3['operator-code']);
				var simPath = valOr(g.sim, '--');
				var simMatch = ('' + simPath).match(/\/(\d+)$/);
				var manufacturer = valOr(g.manufacturer, modems[targetIndex].manufacturer);
				var model = dedupModelName(manufacturer, valOr(g.model, modems[targetIndex].model));
				var primaryPort = valOr(g['primary-port'], '--');
				var portsList = Array.isArray(g.ports) ? g.ports.join(', ') : primaryPort;
				var drivers = Array.isArray(g.drivers) ? g.drivers.join(', ') : valOr(g.plugin, '');
				var mState = valOr(g.state, 'connected');

				// Sync operator and state back into modems entry so dropdown never displays [unknown]
				modems[targetIndex].operator = opName;
				modems[targetIndex].state = mState;
				modems[targetIndex].number = valOr(ownNum, '--');

				var revision = valOr(g.revision, valOr(g['hardware-revision'], valOr(g['carrier-configuration-revision'], '--')));
				if (revision === '--') {
					var snM = model.match(/Modem_SN:([0-9A-Za-z]+)/);
					if (snM && drivers) revision = 'SN:' + snM[1] + ' (驱动: ' + drivers + ')';
					else if (drivers) revision = '驱动: ' + drivers + ' (' + valOr(g.plugin, 'Generic') + ')';
				}

				var simPromise = simMatch ? runMmcliDirect([ '-i', simMatch[1], '-J' ]).then(function(sres) {
					var sp = {};
					try {
						var sj = JSON.parse(sres.stdout);
						sp = (sj && sj.sim && sj.sim.properties) ? sj.sim.properties : {};
					} catch (e) {}
					return {
						path: simPath,
						iccid: valOr(sp.iccid, '--'),
						imsi: valOr(sp.imsi, '--'),
						operator_name: valOr(sp['operator-name'], '--'),
						operator_code: valOr(sp['operator-code'], '--')
					};
				}) : Promise.resolve({ path: simPath, iccid: '--', imsi: '--', operator_name: '--', operator_code: '--' });

				return Promise.all([
					simPromise,
					directGetMessagingStorage(targetId, primaryPort),
					directGetSignalAndBearer(targetId, g.bearers)
				]).then(function(extra) {
					var simObj = extra[0];
					var stInfo = extra[1];
					var extInfo = extra[2];
					return {
						found: true,
						modem_id: targetId,
						modems: modems,
						status: {
							dbus_path: valOr(md['dbus-path'], '/org/freedesktop/ModemManager1/Modem/' + targetId),
							manufacturer: manufacturer,
							model: model,
							revision: revision,
							imei: valOr(g3.imei, valOr(g['equipment-identifier'], '--')),
							device: valOr(g.device, '--'),
							primary_port: primaryPort,
							ports: portsList,
							plugin: valOr(g.plugin, '--'),
							drivers: drivers,
							state: mState,
							failed_reason: valOr(g['state-failed-reason'], ''),
							power_state: valOr(g['power-state'], '--'),
							access_tech: valOr(tech, '--'),
							signal_quality: isNaN(sigVal) ? 0 : sigVal,
							signal_ext: extInfo.signal_ext,
							bearer_info: extInfo.bearer_info,
							own_number: valOr(ownNum, '--'),
							operator_name: opName,
							operator_code: valOr(g3['operator-code'], simObj.operator_code),
							registration_state: valOr(g3['registration-state'], '--'),
							default_sms_storage: stInfo.default_storage,
							supported_sms_storages: stInfo.supported_storages,
							sim: simObj
						}
					};
				});
			}

			return runMmcliDirect([ '-m', targetId, '-K' ]).then(function(kres) {
				var kv = parseKvOutput(kres.stdout);
				var opName = formatOperatorCn(kv['modem.3gpp.operator-name'], kv['modem.3gpp.operator-code']);
				var manufacturer = valOr(kv['modem.generic.manufacturer'], modems[targetIndex].manufacturer);
				var model = dedupModelName(manufacturer, valOr(kv['modem.generic.model'], modems[targetIndex].model));
				var primaryPort = valOr(kv['modem.generic.primary-port'], '--');
				var mState = valOr(kv['modem.generic.state'], 'connected');

				modems[targetIndex].operator = opName;
				modems[targetIndex].state = mState;

				return directGetMessagingStorage(targetId, primaryPort).then(function(stInfo) {
					return {
						found: true,
						modem_id: targetId,
						modems: modems,
						status: {
							dbus_path: valOr(kv['modem.dbus-path'], '/org/freedesktop/ModemManager1/Modem/' + targetId),
							manufacturer: manufacturer,
							model: model,
							revision: valOr(kv['modem.generic.revision'], valOr(kv['modem.generic.hardware-revision'], '驱动: cdc_mbim')),
							imei: valOr(kv['modem.3gpp.imei'], valOr(kv['modem.generic.equipment-identifier'], '--')),
							device: valOr(kv['modem.generic.device'], '--'),
							primary_port: primaryPort,
							ports: primaryPort,
							plugin: valOr(kv['modem.generic.plugin'], '--'),
							state: mState,
							failed_reason: valOr(kv['modem.generic.state-failed-reason'], ''),
							power_state: valOr(kv['modem.generic.power-state'], '--'),
							access_tech: valOr(kv['modem.generic.access-technologies.value[1]'], '--').toUpperCase(),
							signal_quality: parseInt(kv['modem.generic.signal-quality.value'] || '0', 10),
							own_number: valOr(kv['modem.generic.own-numbers.value[1]'], '--'),
							operator_name: opName,
							operator_code: valOr(kv['modem.3gpp.operator-code'], '--'),
							registration_state: valOr(kv['modem.3gpp.registration-state'], '--'),
							default_sms_storage: stInfo.default_storage,
							supported_sms_storages: stInfo.supported_storages,
							sim: {
								path: valOr(kv['modem.generic.sim'], '--'),
								iccid: '--',
								imsi: '--',
								operator_name: opName,
								operator_code: '--'
							}
						}
					};
				});
			});
		});
	});
}

function directSyncDb(modemId) {
	return runForwarderDirect([ '--sync-db' ]).then(function(res) {
		if (res && Array.isArray(res.messages)) {
			return {
				sms: { modem_id: modemId, count: res.messages.length, messages: res.messages },
				calls: { modem_id: modemId, count: Array.isArray(res.calls) ? res.calls.length : 0, calls: res.calls || [] }
			};
		}
		return {
			sms: { modem_id: modemId, count: 0, messages: [] },
			calls: { modem_id: modemId, count: 0, calls: [] }
		};
	});
}

function directListSms(modemId) {
	return directSyncDb(modemId).then(function(d) { return d.sms; });
}

function directListCalls(modemId) {
	return directSyncDb(modemId).then(function(d) { return d.calls; });
}

return view.extend({
	currentModem: '0',
	activeTab: 'sms',
	smsFilter: 'all',
	smsSearch: '',
	callFilter: 'all',
	callSearch: '',
	selectedSms: {},
	selectedCalls: {},
	cachedStatus: null,
	cachedSms: [],
	cachedCalls: [],
	atCommandInput: 'ATI',
	atLogHistory: [],
	atRunning: false,
	atLogPreNode: null,
	atClearLogBtnNode: null,

	formatAtLogText: function() {
		var self = this;
		if (!self.atLogHistory || self.atLogHistory.length === 0) {
			return _('尚未执行 AT 指令。\n提示：点击上方快捷按钮或输入 AT 指令后点击“发送 AT 命令”，底层将通过 ModemManager 原生接口 (mmcli -m ') +
				self.currentModem + _(' --command="...") 执行并返回结果。');
		}
		return self.atLogHistory.map(function(entry) {
			var statusTag = entry.error ? '[错误]' : '[成功]';
			return '[' + entry.time + '] ' + statusTag + ' $ mmcli -m ' + entry.modem + ' --command="' + entry.command + '"\n' +
				entry.output + '\n' +
				'------------------------------------------------------------';
		}).join('\n');
	},
	atPresets: null,
	forwardConfig: null,
	forwardRunning: false,
	forwardLogs: '',
	forwardLogPreNode: null,
	forwardStatusBadgeNode: null,
	updateSmsTableFn: null,
	updateCallsTableFn: null,

	fetchAllData: function() {
		var self = this;
		return callGetStatus(self.currentModem).catch(function() {
			return {};
		}).then(function(statusRes) {
			if (statusRes && typeof statusRes.found === 'boolean') {
				if (statusRes.modem_id) self.currentModem = statusRes.modem_id;
				return Promise.all([
					Promise.resolve(statusRes),
					callListSms(self.currentModem).catch(function() { return null; }),
					callListCalls(self.currentModem).catch(function() { return null; })
				]).then(function(resArr) {
					if (resArr[1] && Array.isArray(resArr[1].messages)) {
						var callsObj = resArr[2] || { calls: [] };
						if (Array.isArray(callsObj.calls)) {
							callsObj.calls.forEach(function(c) {
								c.timestamp = getLocalCallTimestamp(self.currentModem, c.id, c.number, c.timestamp);
							});
						}
						return [ resArr[0], resArr[1], callsObj ];
					}
					return directSyncDb(self.currentModem).then(function(dbRes) {
						return [ resArr[0], dbRes.sms, dbRes.calls ];
					});
				});
			}
			return directGetStatus(self.currentModem).then(function(dStatus) {
				if (dStatus && dStatus.modem_id) self.currentModem = dStatus.modem_id;
				return directSyncDb(self.currentModem).then(function(dbRes) {
					return [ dStatus || { found: false }, dbRes.sms, dbRes.calls ];
				});
			});
		});
	},

	loadAtPresets: function() {
		var self = this;
		if (self.atPresets && self.atPresets.length > 0) return Promise.resolve(self.atPresets);
		return callGetAtPresets().catch(function() { return {}; }).then(function(res) {
			if (res && Array.isArray(res.presets) && res.presets.length > 0) {
				self.atPresets = res.presets;
				return self.atPresets;
			}
			try {
				var raw = window.localStorage.getItem('luci_modemmanager_at_presets_v1');
				if (raw) {
					var parsed = JSON.parse(raw);
					if (Array.isArray(parsed) && parsed.length > 0) {
						self.atPresets = parsed;
						return self.atPresets;
					}
				}
			} catch (e) {}
			self.atPresets = JSON.parse(JSON.stringify(DEFAULT_AT_PRESETS));
			return self.atPresets;
		});
	},

	saveAtPresets: function(presets) {
		var self = this;
		self.atPresets = presets;
		try {
			window.localStorage.setItem('luci_modemmanager_at_presets_v1', JSON.stringify(presets));
		} catch (e) {}
		callSaveAtPresets(presets).catch(function() {
			return fs.write('/etc/modemmanager_at_presets.json', JSON.stringify(presets, null, 2));
		});
		self.updateContainers();
	},

	openEditPresetModal: function(idx) {
		var self = this;
		var item = self.atPresets[idx];
		if (!item) return;

		var cmdInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:100%;font-family:monospace;font-weight:600;',
			'value': item.cmd
		});
		var descInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:100%;margin-top:6px;',
			'value': item.desc
		});

		ui.showModal(_('编辑 AT 快捷指令') + ' (#' + (idx + 1) + ')', [
			E('div', { 'class': 'cbi-section' }, [
				E('label', { 'style': 'font-weight:600;display:block;margin-bottom:4px;' }, _('AT 命令：')),
				cmdInput,
				E('label', { 'style': 'font-weight:600;display:block;margin-top:10px;margin-bottom:4px;' }, _('指令说明名称：')),
			descInput
			]),
			E('div', { 'class': 'right', 'style': 'margin-top:14px;' }, [
				E('button', {
					'class': 'btn',
					'click': function() {
						ui.hideModal();
						self.openManageAtPresetsModal();
					}
				}, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': function() {
						var c = (cmdInput.value || '').trim();
						var d = (descInput.value || '').trim();
						if (!c) {
							ui.addNotification(null, E('p', _('AT 命令不能为空！')), 'warning');
							return;
						}
						if (/^at/i.test(c)) c = 'AT' + c.substring(2);
						self.atPresets[idx] = { cmd: c, desc: d || c };
						self.saveAtPresets(self.atPresets);
						ui.hideModal();
						self.openManageAtPresetsModal();
					}
				}, _('保存修改'))
			])
		]);
	},

	openAddPresetModal: function(prefillCmd) {
		var self = this;
		var cmdInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:100%;font-family:monospace;font-weight:600;',
			'value': prefillCmd || 'AT'
		});
		var descInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:100%;margin-top:6px;',
			'placeholder': '例如：查询当前小区基站信息'
		});

		ui.showModal(_('添加到常用 AT 指令库'), [
			E('div', { 'class': 'cbi-section' }, [
				E('label', { 'style': 'font-weight:600;display:block;margin-bottom:4px;' }, _('AT 命令：')),
				cmdInput,
				E('label', { 'style': 'font-weight:600;display:block;margin-top:10px;margin-bottom:4px;' }, _('指令说明名称：')),
				descInput
			]),
			E('div', { 'class': 'right', 'style': 'margin-top:14px;' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': function() {
						var c = (cmdInput.value || '').trim();
						var d = (descInput.value || '').trim();
						if (!c) {
							ui.addNotification(null, E('p', _('AT 命令不能为空！')), 'warning');
							return;
						}
						if (/^at/i.test(c)) c = 'AT' + c.substring(2);
						if (!Array.isArray(self.atPresets)) self.atPresets = JSON.parse(JSON.stringify(DEFAULT_AT_PRESETS));
						self.atPresets.push({ cmd: c, desc: d || c });
						self.saveAtPresets(self.atPresets);
						ui.hideModal();
						ui.addNotification(null, E('p', _('已成功添加 AT 指令: ') + c), 'info');
					}
				}, _('保存添加'))
			])
		]);
	},

	openManageAtPresetsModal: function() {
		var self = this;
		if (!Array.isArray(self.atPresets) || self.atPresets.length === 0) {
			self.atPresets = JSON.parse(JSON.stringify(DEFAULT_AT_PRESETS));
		}

		var newCmdInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:190px;font-family:monospace;font-weight:600;',
			'placeholder': '例如：AT+QENG="servingcell"'
		});
		var newDescInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'flex:1;min-width:210px;',
			'placeholder': '例如：查询当前服务小区参数与频段'
		});

		var tableRows = self.atPresets.map(function(item, idx) {
			var upBtn = E('button', {
				'class': 'btn',
				'style': 'padding:2px 6px;margin-right:3px;',
				'disabled': idx === 0 ? 'disabled' : null,
				'click': function() {
					if (idx > 0) {
						var tmp = self.atPresets[idx];
						self.atPresets[idx] = self.atPresets[idx - 1];
						self.atPresets[idx - 1] = tmp;
						self.saveAtPresets(self.atPresets);
						ui.hideModal();
						self.openManageAtPresetsModal();
					}
				}
			}, _('上移'));

			var downBtn = E('button', {
				'class': 'btn',
				'style': 'padding:2px 6px;margin-right:6px;',
				'disabled': idx === (self.atPresets.length - 1) ? 'disabled' : null,
				'click': function() {
					if (idx < self.atPresets.length - 1) {
						var tmp = self.atPresets[idx];
						self.atPresets[idx] = self.atPresets[idx + 1];
						self.atPresets[idx + 1] = tmp;
						self.saveAtPresets(self.atPresets);
						ui.hideModal();
						self.openManageAtPresetsModal();
					}
				}
			}, _('下移'));

			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td', 'style': 'width:40px;text-align:center;' }, '' + (idx + 1)),
				E('td', { 'class': 'td', 'style': 'font-family:monospace;font-weight:600;min-width:150px;' }, item.cmd),
				E('td', { 'class': 'td', 'style': 'min-width:220px;font-size:12px;color:var(--mm-text-primary);' }, item.desc || item.cmd),
				E('td', { 'class': 'td', 'style': 'text-align:right;white-space:nowrap;' }, [
					upBtn,
					downBtn,
					E('button', {
						'class': 'btn cbi-button-action',
						'style': 'padding:2px 8px;margin-right:4px;',
						'click': function() {
							ui.hideModal();
							self.openEditPresetModal(idx);
						}
					}, _('编辑')),
					E('button', {
						'class': 'btn cbi-button-negative',
						'style': 'padding:2px 8px;',
						'click': function() {
							if (confirm(_('确定要删除指令预设 "') + item.cmd + '" 吗？')) {
								self.atPresets.splice(idx, 1);
								self.saveAtPresets(self.atPresets);
								ui.hideModal();
								self.openManageAtPresetsModal();
							}
						}
					}, _('删除'))
				])
			]);
		});

		var table = E('table', { 'class': 'table cbi-section-table', 'style': 'margin-top:10px;' }, [
			E('thead', {}, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th', 'style': 'width:40px;text-align:center;' }, '#'),
					E('th', { 'class': 'th', 'style': 'width:160px;' }, _('AT 命令')),
					E('th', { 'class': 'th' }, _('指令说明名称')),
					E('th', { 'class': 'th', 'style': 'width:180px;text-align:right;' }, _('操作'))
				])
			]),
			E('tbody', {}, tableRows)
		]);

		var modalBody = [
			E('div', { 'class': 'cbi-section', 'style': 'margin-bottom:14px;padding:12px;background:var(--mm-subcard-bg);border:1px solid var(--mm-border);color:var(--mm-text-primary);border-radius:6px;' }, [
				E('h4', { 'style': 'margin-top:0;margin-bottom:8px;' }, _('添加新自定义 AT 指令')),
				E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;' }, [
					E('label', { 'style': 'font-size:12px;font-weight:600;' }, _('命令:')),
					newCmdInput,
					E('label', { 'style': 'font-size:12px;font-weight:600;' }, _('说明:')),
					newDescInput,
					E('button', {
						'class': 'btn cbi-button-action important',
						'click': function() {
							var cmd = (newCmdInput.value || '').trim();
							var desc = (newDescInput.value || '').trim();
							if (!cmd) {
								ui.addNotification(null, E('p', _('AT 命令不能为空！')), 'warning');
								return;
							}
							if (/^at/i.test(cmd)) cmd = 'AT' + cmd.substring(2);
							if (!desc) desc = cmd;
							self.atPresets.push({ cmd: cmd, desc: desc });
							self.saveAtPresets(self.atPresets);
							ui.hideModal();
							self.openManageAtPresetsModal();
						}
					}, _('添加指令'))
				])
			]),
			E('div', { 'style': 'max-height:360px;overflow-y:auto;border:1px solid var(--mm-border);border-radius:6px;padding:4px;' }, [ table ]),
			E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-top:14px;' }, [
				E('button', {
					'class': 'btn cbi-button-neutral',
					'click': function() {
						if (confirm(_('确定要将所有 AT 预设指令恢复为初始默认值吗？自定义添加的指令将会被重置。'))) {
							self.atPresets = JSON.parse(JSON.stringify(DEFAULT_AT_PRESETS));
							self.saveAtPresets(self.atPresets);
							ui.hideModal();
							self.openManageAtPresetsModal();
						}
					}
				}, _('恢复系统默认指令库')),
				E('button', {
					'class': 'btn',
					'click': function() {
						ui.hideModal();
					}
				}, _('完成并关闭'))
			])
		];

		ui.showModal(_('管理快捷 AT 指令库 (支持添加、编辑与删除)'), modalBody);
	},
	updateForwardBadgeNode: function() {
		var self = this;
		if (self.forwardStatusBadgeNode) {
			self.forwardStatusBadgeNode.style.background = self.forwardRunning ? '#2ea043' : '#6e7781';
			self.forwardStatusBadgeNode.textContent = self.forwardRunning ? _('后台守护进程运行中') : _('后台守护进程未运行');
		}
	},

	loadForwardData: function() {
		var self = this;
		return Promise.all([
			callGetForwardConfig().catch(function() { return {}; }),
			callGetForwardLogs().catch(function() { return {}; })
		]).then(function(arr) {
			var cres = arr[0] || {};
			var lres = arr[1] || {};
			if (typeof cres.running === 'boolean' && cres.config) {
				self.forwardRunning = !!cres.running;
				self.forwardConfig = cres.config;
				self.forwardLogs = lres.logs || '';
				return null;
			}
			return runForwarderDirect([ '--status' ]).then(function(dres) {
				if (dres && typeof dres.running === 'boolean') {
					self.forwardRunning = !!dres.running;
					self.forwardConfig = dres.config || defaultForwardConfig();
					self.forwardLogs = dres.logs || '';
				} else {
					self.forwardRunning = false;
					self.forwardConfig = defaultForwardConfig();
				}
			});
		}).then(function() {
			var def = defaultForwardConfig();
			if (!self.forwardConfig || typeof self.forwardConfig !== 'object') self.forwardConfig = def;
			self.forwardConfig.channels = self.forwardConfig.channels || {};
			Object.keys(def.channels).forEach(function(k) {
				self.forwardConfig.channels[k] = Object.assign({}, def.channels[k], self.forwardConfig.channels[k] || {});
			});
		});
	},

	refreshForwardStatusAndLogs: function() {
		var self = this;
		return Promise.all([
			callGetForwardConfig().catch(function() { return {}; }),
			callGetForwardLogs().catch(function() { return {}; })
		]).then(function(arr) {
			var cres = arr[0] || {};
			var lres = arr[1] || {};
			if (typeof cres.running === 'boolean') {
				self.forwardRunning = !!cres.running;
				self.forwardLogs = lres.logs || '';
				self.updateForwardBadgeNode();
				if (self.forwardLogPreNode) {
					self.forwardLogPreNode.textContent = self.forwardLogs || _('暂无短信转发日志...');
				}
				return;
			}
			return runForwarderDirect([ '--status' ]).then(function(dres) {
				if (dres && typeof dres.running === 'boolean') {
					self.forwardRunning = !!dres.running;
					self.forwardLogs = dres.logs || '';
					self.updateForwardBadgeNode();
					if (self.forwardLogPreNode) {
						self.forwardLogPreNode.textContent = self.forwardLogs || _('暂无短信转发日志...');
					}
				}
			});
		});
	},

	load: function() {
		var self = this;
		return Promise.all([
			self.fetchAllData(),
			self.loadAtPresets(),
			self.loadForwardData()
		]).then(function(arr) {
			return arr[0];
		});
	},

	formatStateBadge: function(state, failedReason) {
		var s = (state || 'unknown').toLowerCase();
		var color = '#6c757d';
		var label = '未知状态 (' + (state || 'unknown') + ')';

		if (s === 'connected') { color = '#2ea043'; label = '已连接数据网络'; }
		else if (s === 'registered') { color = '#0969da'; label = '已注册运营商网络'; }
		else if (s === 'connecting') { color = '#d29922'; label = '正在拨号连接...'; }
		else if (s === 'searching') { color = '#d29922'; label = '正在搜索移动网络...'; }
		else if (s === 'enabled') { color = '#0969da'; label = '已启用 (待注册)'; }
		else if (s === 'locked') { color = '#cf222e'; label = 'SIM卡已锁定 (需PIN码)'; }
		else if (s === 'failed') {
			color = '#cf222e';
			label = failedReason === 'sim-missing' ? '未检测到 SIM 卡 (sim-missing)' : ('模块异常 (' + (failedReason || 'failed') + ')');
		}
		else if (s === 'disabled') { color = '#6e7781'; label = '模块已禁用 (Disabled)'; }
		else if (s === 'initializing') { color = '#8250df'; label = '正在初始化...'; }

		return E('span', {
			'style': 'display:inline-block;padding:2px 10px;border-radius:12px;font-size:12px;font-weight:600;color:#fff;background:' + color
		}, label);
	},

	formatSmsStateBadge: function(state) {
		var s = (state || 'unknown').toLowerCase();
		var bg = '#6e7781';
		var text = '未知 (' + s + ')';
		if (s === 'received') { bg = '#1f883d'; text = '收件箱'; }
		else if (s === 'sent') { bg = '#0969da'; text = '已发送'; }
		else if (s === 'stored') { bg = '#9a6700'; text = '草稿 / 本地存储'; }
		else if (s === 'receiving') { bg = '#8250df'; text = '正在接收分片...'; }
		else if (s === 'sending') { bg = '#8250df'; text = '正在发送...'; }

		return E('span', {
			'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;color:#fff;background:' + bg
		}, text);
	},

	formatStorageName: function(storage) {
		var st = (storage || '').toLowerCase();
		if (!st || st === '--' || st === 'unknown') return 'MBIM 统一存储';
		return SMS_STORAGE_CN[st] || storage;
	},

	formatCallDirectionBadge: function(dir) {
		var d = (dir || 'unknown').toLowerCase();
		var bg = '#6e7781';
		var text = '未知方向';
		if (d === 'incoming') { bg = '#1f883d'; text = '呼入来电'; }
		else if (d === 'outgoing') { bg = '#0969da'; text = '呼出去电'; }

		return E('span', {
			'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;color:#fff;background:' + bg
		}, text);
	},

	formatCallStateBadge: function(state) {
		var s = (state || 'unknown').toLowerCase();
		var bg = '#6e7781';
		var text = '未知状态';
		if (s === 'active') { bg = '#1f883d'; text = '正在通话中'; }
		else if (s === 'ringing-in') { bg = '#d29922'; text = '来电振铃中'; }
		else if (s === 'ringing-out') { bg = '#9a6700'; text = '去电呼叫中'; }
		else if (s === 'terminated') { bg = '#57606a'; text = '通话已结束'; }
		else if (s === 'held') { bg = '#8250df'; text = '通话保持中'; }
		else if (s === 'waiting') { bg = '#8250df'; text = '呼叫等待中'; }

		return E('span', {
			'style': 'display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;color:#fff;background:' + bg
		}, text);
	},

	formatCallReason: function(reason, direction, state) {
		var r = (reason || '').toLowerCase();
		if (r && r !== '--' && r !== 'unknown' && CALL_REASON_CN[r]) {
			return CALL_REASON_CN[r];
		}
		var d = (direction || '').toLowerCase();
		var s = (state || '').toLowerCase();
		if (s === 'terminated') {
			if (d === 'incoming') return '未接来电 / 对方挂断';
			if (d === 'outgoing') return '主叫通话已结束';
			return '通话已结束';
		}
		if (s === 'ringing-in') return '对方正在呼叫本机';
		if (s === 'ringing-out') return '正在呼叫等待接听';
		if (s === 'active') return '语音通道已建立';
		return (reason && reason !== '--' && reason !== 'unknown') ? reason : '已记录';
	},

	refreshData: function(isBackgroundPoll) {
		var self = this;
		var pAll = self.fetchAllData();
		var pFwd = (self.activeTab === 'forward')
			? self.refreshForwardStatusAndLogs()
			: Promise.resolve();
		return Promise.all([ pAll, pFwd ]).then(function(arr) {
			var results = arr[0];
			self.cachedStatus = results[0] || { found: false };
			self.cachedSms = (results[1] && Array.isArray(results[1].messages)) ? results[1].messages : [];
			self.cachedCalls = (results[2] && Array.isArray(results[2].calls)) ? results[2].calls : [];
			if (isBackgroundPoll) {
				var activeEl = document.activeElement;
				var inStatusSelect = activeEl && self.statusContainer && self.statusContainer.contains(activeEl);
				if (self.statusContainer && !inStatusSelect) {
					dom.content(self.statusContainer, self.renderStatusCard());
				}
				if (self.tabsContainer) {
					dom.content(self.tabsContainer, self.renderTabsBar());
				}
				if (self.activeTab === 'sms' && typeof self.updateSmsTableFn === 'function') {
					self.updateSmsTableFn();
				} else if (self.activeTab === 'calls' && typeof self.updateCallsTableFn === 'function') {
					self.updateCallsTableFn();
				}
			} else {
				self.updateContainers();
			}
		});
	},

	openSendSmsModal: function(prefillNumber) {
		var self = this;
		var numInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:100%;margin-bottom:10px;',
			'placeholder': '例如：10086、10010 或 +8613800138000',
			'value': prefillNumber || ''
		});
		var textInput = E('textarea', {
			'class': 'cbi-input-textarea',
			'style': 'width:100%;height:110px;',
			'placeholder': '请输入短信正文（原生支持 UTF-8 中文及长短信自动拆分发送）...'
		});

		ui.showModal(_('发送新短信') + ' (模块 #' + self.currentModem + ')', [
			E('div', { 'class': 'cbi-section' }, [
				E('label', { 'style': 'font-weight:600;display:block;margin-bottom:4px;' }, _('收件人电话号码：')),
				numInput,
				E('label', { 'style': 'font-weight:600;display:block;margin-bottom:4px;' }, _('短信内容（支持中文）：')),
				textInput
			]),
			E('div', { 'class': 'right', 'style': 'margin-top:12px;' }, [
				E('button', {
					'class': 'btn',
					'click': ui.hideModal
				}, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': ui.createHandlerFn(self, function() {
						var num = (numInput.value || '').trim();
						var txt = textInput.value || '';
						if (!num || !txt) {
							ui.addNotification(null, E('p', _('收件人号码和短信内容不能为空！')), 'warning');
							return;
						}
						ui.hideModal();
						return callSendSms(self.currentModem, num, txt).then(function(res) {
							if (res && typeof res.code === 'number') {
								if (res.code === 0) {
									ui.addNotification(null, E('p', res.message || _('短信发送成功！')), 'info');
								} else {
									ui.addNotification(null, E('p', res.error || _('短信发送失败')), 'danger');
								}
								return self.refreshData();
							}
							return runForwarderDirect([ '--db-send-sms', self.currentModem, num, txt ]).then(function(dres) {
								if (dres && dres.code === 0) {
									ui.addNotification(null, E('p', dres.message || _('短信发送成功并已归档至本地数据库')), 'info');
								} else {
									ui.addNotification(null, E('p', (dres && dres.error) ? dres.error : _('发送失败')), 'danger');
								}
								return self.refreshData();
							});
						});
					})
				}, _('立即发送'))
			])
		]);
	},

	openDialModal: function(prefillNumber) {
		var self = this;
		var numInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:100%;',
			'placeholder': '例如：10086 或 13800138000',
			'value': prefillNumber || ''
		});

		ui.showModal(_('发起语音呼叫') + ' (模块 #' + self.currentModem + ')', [
			E('div', { 'class': 'cbi-section' }, [
				E('label', { 'style': 'font-weight:600;display:block;margin-bottom:6px;' }, _('要拨打的电话号码：')),
				numInput
			]),
			E('div', { 'class': 'right', 'style': 'margin-top:12px;' }, [
				E('button', {
					'class': 'btn',
					'click': ui.hideModal
				}, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': ui.createHandlerFn(self, function() {
						var num = (numInput.value || '').trim();
						if (!num) {
							ui.addNotification(null, E('p', _('请输入要拨打的电话号码！')), 'warning');
							return;
						}
						ui.hideModal();
						return callCreateCall(self.currentModem, num).then(function(res) {
							if (res && typeof res.code === 'number') {
								if (res.code === 0) {
									ui.addNotification(null, E('p', res.message || _('已发起语音呼叫')), 'info');
								} else {
									ui.addNotification(null, E('p', res.error || _('语音呼叫失败')), 'danger');
								}
								return self.refreshData();
							}
							return runMmcliDirect([ '-m', self.currentModem, "--voice-create-call=number='" + num.replace(/'/g, '') + "'" ]).then(function(cres) {
								var m = (cres.stdout || '').match(/\/Call\/(\d+)/);
								if (!m) {
									ui.addNotification(null, E('p', _('创建呼叫失败: ') + (cres.stderr || cres.stdout)), 'danger');
									return self.refreshData();
								}
								getLocalCallTimestamp(self.currentModem, m[1], num, nowFormatted());
								return runMmcliDirect([ '-o', m[1], '--start' ]).then(function() {
									ui.addNotification(null, E('p', _('已发起呼叫 (ID #') + m[1] + ')'), 'info');
									return self.refreshData();
								});
							});
						});
					})
				}, _('开始呼叫'))
			])
		]);
	},

	handleDeleteSms: function(ids) {
		var self = this;
		var idArr = Array.isArray(ids) ? ids : [ ids ];
		var idStr = idArr.join(',');
		if (!idStr) return Promise.resolve();

		return callDeleteSms(self.currentModem, idStr).then(function(res) {
			if (res && typeof res.code === 'number') {
				if (res.code === 0) {
					idArr.forEach(function(id) { delete self.selectedSms[id]; });
					ui.addNotification(null, E('p', _('已成功删除短信记录 (编号: ') + idStr + ')'), 'info');
				} else {
					ui.addNotification(null, E('p', JSON.stringify(res.errors || '删除失败')), 'danger');
				}
				return self.refreshData();
			}
			return runForwarderDirect([ '--db-delete-sms', self.currentModem, idStr ]).then(function() {
				idArr.forEach(function(id) { delete self.selectedSms[id]; });
				ui.addNotification(null, E('p', _('已成功删除短信记录 (编号: ') + idStr + ')'), 'info');
				return self.refreshData();
			});
		});
	},

	handleDeleteAllSms: function() {
		var self = this;
		ui.showModal(_('确认清空全部短信'), [
			E('p', _('确定要删除当前调制解调器 (模块 #') + self.currentModem + _(') 上的所有短信记录吗？此操作不可恢复。')),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-negative',
					'click': ui.createHandlerFn(self, function() {
						ui.hideModal();
						var allIds = self.cachedSms.map(function(m) { return m.id; });
						return self.handleDeleteSms(allIds);
					})
				}, _('确认全部删除'))
			])
		]);
	},

	handleDeleteCall: function(ids) {
		var self = this;
		var idArr = Array.isArray(ids) ? ids : [ ids ];
		var idStr = idArr.join(',');
		if (!idStr) return Promise.resolve();

		return callDeleteCall(self.currentModem, idStr).then(function(res) {
			if (res && typeof res.code === 'number') {
				if (res.code === 0) {
					idArr.forEach(function(id) {
						delete self.selectedCalls[id];
						removeLocalCallTimestamp(self.currentModem, id);
					});
					ui.addNotification(null, E('p', _('已成功删除通话记录 (编号: ') + idStr + ')'), 'info');
				} else {
					ui.addNotification(null, E('p', JSON.stringify(res.errors || '删除失败')), 'danger');
				}
				return self.refreshData();
			}
			return runForwarderDirect([ '--db-delete-call', self.currentModem, idStr ]).then(function() {
				idArr.forEach(function(id) {
					delete self.selectedCalls[id];
					removeLocalCallTimestamp(self.currentModem, id);
				});
				ui.addNotification(null, E('p', _('已成功删除通话记录 (编号: ') + idStr + ')'), 'info');
				return self.refreshData();
			});
		});
	},

	handleDeleteAllCalls: function() {
		var self = this;
		ui.showModal(_('确认清空全部通话记录'), [
			E('p', _('确定要删除当前调制解调器 (模块 #') + self.currentModem + _(') 上的所有通话记录吗？此操作不可恢复。')),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-negative',
					'click': ui.createHandlerFn(self, function() {
						ui.hideModal();
						var allIds = self.cachedCalls.map(function(c) { return c.id; });
						return self.handleDeleteCall(allIds);
					})
				}, _('确认全部删除'))
			])
		]);
	},

	executeAtCommand: function(rawCmd) {
		var self = this;
		var cmd = (rawCmd || '').trim();
		if (!cmd) {
			ui.addNotification(null, E('p', _('请输入要执行的 AT 命令！')), 'warning');
			return Promise.resolve();
		}
		// Normalize leading lowercase 'at' to uppercase 'AT' so mmcli --command does not prepend 'AT' twice
		if (/^at/i.test(cmd)) {
			cmd = 'AT' + cmd.substring(2);
		}
		self.atCommandInput = cmd;
		self.atRunning = true;

		var appendHistory = function(commandStr, outputStr, isErr) {
			self.atLogHistory.unshift({
				time: nowFormatted(),
				modem: self.currentModem,
				command: commandStr,
				output: outputStr,
				error: !!isErr
			});
			if (self.atLogHistory.length > 50) self.atLogHistory.pop();
			self.atRunning = false;
			if (self.atLogPreNode) {
				self.atLogPreNode.textContent = self.formatAtLogText();
			} else {
				self.updateContainers();
			}
			if (self.atClearLogBtnNode) {
				self.atClearLogBtnNode.removeAttribute('disabled');
			}
		};

		return callSendAt(self.currentModem, cmd).catch(function() {
			return null;
		}).then(function(res) {
			if (res && typeof res.code === 'number') {
				appendHistory(res.command || cmd, res.output || '(无返回内容)', res.code !== 0);
				return;
			}
			// Direct mmcli fallback
			return runMmcliDirect([ '-m', '' + self.currentModem, '--command=' + cmd ]).then(function(dres) {
				var combined = ((dres.stdout || '') + '\n' + (dres.stderr || '')).trim();
				if (dres.code !== 0 && /debug mode/i.test(combined)) {
					return fs.exec('/usr/bin/modemmanager-enable-at', []).catch(function() {
						return null;
					}).then(function() {
						return runMmcliDirect([ '-m', '' + self.currentModem, '--command=' + cmd ]);
					}).then(function(retryRes) {
						var out2 = ((retryRes.stdout || '') + '\n' + (retryRes.stderr || '')).trim();
						if (retryRes.code === 0) {
							var m2 = out2.match(/response:\s*'(.*)'/s);
							if (m2) out2 = m2[1];
						}
						appendHistory(cmd, out2 || '(无返回内容)', retryRes.code !== 0);
					});
				}
				var out = combined;
				if (dres.code === 0) {
					var m = out.match(/response:\s*'(.*)'/s);
					if (m) out = m[1];
				}
				appendHistory(cmd, out || '(无返回内容)', dres.code !== 0);
			});
		});
	},

	renderStatusCard: function() {
		var self = this;
		var statusRes = self.cachedStatus || {};
		var modems = statusRes.modems || [];

		var modemSelect = E('select', {
			'class': 'cbi-input-select',
			'style': 'min-width:260px;margin-right:8px;',
			'change': ui.createHandlerFn(self, function(ev) {
				self.currentModem = ev.target.value;
				self.selectedSms = {};
				self.selectedCalls = {};
				return self.refreshData();
			})
		}, modems.length > 0 ? modems.map(function(m) {
			return E('option', {
				'value': m.id,
				'selected': (m.id === self.currentModem) ? 'selected' : null
			}, formatModemOptionText(m, self.currentModem, statusRes.status));
		}) : [ E('option', { 'value': '0' }, _('未检测到可用蜂窝模块')) ]);

		var topBar = E('div', {
			'style': 'display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:10px;margin-bottom:14px;padding:12px 16px;background:var(--mm-subcard-bg);border:1px solid var(--mm-border);color:var(--mm-text-primary);border-radius:8px;'
		}, [
			E('div', { 'style': 'display:flex;align-items:center;flex-wrap:wrap;gap:8px;' }, [
				E('strong', { 'style': 'margin-right:4px;' }, _('当前调制解调器：')),
				modemSelect,
				E('button', {
					'class': 'btn cbi-button-action',
					'click': ui.createHandlerFn(self, function() {
						return self.refreshData();
					})
				}, _('刷新状态')),
				E('button', {
					'class': 'btn',
					'click': ui.createHandlerFn(self, function() {
						return callModemAction(self.currentModem, 'scan').then(function(res) {
							if (!res || typeof res.code !== 'number') {
								return runMmcliDirect([ '-S' ]);
							}
						}).then(function() {
							return self.refreshData();
						});
					})
				}, _('重新扫描模块'))
			]),
			E('div', { 'style': 'font-size:12px;color:var(--mm-text-secondary);font-weight:600;' },
				_('短信总数：') + self.cachedSms.length + _(' 条 | 通话记录：') + self.cachedCalls.length + _(' 条'))
		]);

		if (!statusRes.found || !statusRes.status) {
			return E('div', {}, [
				topBar,
				E('div', { 'class': 'alert-message warning' }, [
					E('h4', _('未检测到活跃的 ModemManager 设备')),
					E('p', statusRes.error || _('请确认已执行 /etc/init.d/rpcd restart 重启 RPCD 服务，并退出重新登录一次 LuCI 页面以刷新权限。'))
				])
			]);
		}

		var st = statusRes.status;
		var sig = parseInt(st.signal_quality || 0, 10);
		var sigColor = sig >= 60 ? '#2ea043' : (sig >= 30 ? '#d29922' : '#cf222e');
		var regText = REG_STATE_CN[(st.registration_state || '').toLowerCase()] || (st.registration_state || '--');

		var signalBar = E('div', { 'style': 'display:flex;flex-direction:column;gap:4px;' }, [
			E('div', { 'style': 'display:flex;align-items:center;gap:8px;' }, [
				E('div', {
					'style': 'width:110px;height:10px;background:var(--mm-bar-track);border-radius:5px;overflow:hidden;'
				}, [
					E('div', {
						'style': 'width:' + Math.min(100, Math.max(0, sig)) + '%;height:100%;background:' + sigColor + ';'
					})
				]),
				E('strong', {}, sig + '%')
			]),
			st.signal_ext ? E('span', { 'style': 'font-size:11px;color:var(--mm-text-secondary);font-weight:normal;' }, st.signal_ext) : ''
		]);

		var brandModel = dedupModelName(st.manufacturer, st.model);
		if (st.manufacturer && st.manufacturer !== '--') {
			brandModel = st.manufacturer + ' ' + brandModel;
		}

		var defStorageCode = st.default_sms_storage;
		if ((!defStorageCode || defStorageCode === '--' || defStorageCode === 'mbim') && self.cachedSms.length > 0 && self.cachedSms[0].storage) {
			defStorageCode = self.cachedSms[0].storage;
		}
		var defStorageLabel = self.formatStorageName(defStorageCode);
		var supStorageLabel = st.supported_sms_storages || 'SIM卡 + 模块自动管理';
		if (supStorageLabel === defStorageCode) {
			supStorageLabel = defStorageLabel;
		}

		var gridItems = [
			[ _('工作状态'), self.formatStateBadge(st.state, st.failed_reason) ],
			[ _('信号质量与参数'), signalBar ],
			[ _('运营商 / 网络制式'), (st.operator_name || '--') + ' / ' + (st.access_tech || '--') + ' (' + regText + ')' ],
			[ _('本机电话号码'), st.own_number || '--' ],
			[ _('模块品牌 / 型号'), brandModel || '--' ],
			[ _('固件 / 硬件驱动信息'), st.revision || '--' ],
			[ _('IMEI 串号'), st.imei || '--' ],
			[ _('SIM卡 ICCID / IMSI'), (st.sim ? st.sim.iccid : '--') + ' / ' + (st.sim ? st.sim.imsi : '--') ],
			[ _('数据存储模式 (自动清空模块)'), '本地数据库持久存储 (模块零占用 | 库内短信 ' + self.cachedSms.length + ' 条)' ],
			[ _('主通信端口 / 承载网络'), (st.primary_port || '--') + (st.bearer_info && st.bearer_info !== '--' ? (' | ' + st.bearer_info) : (' (' + (st.dbus_path || '--') + ')')) ]
		];

		var infoGrid = E('div', {
			'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:10px;margin-bottom:16px;'
		}, gridItems.map(function(item) {
			return E('div', {
				'style': 'padding:10px 14px;background:var(--mm-card-bg);border:1px solid var(--mm-border);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);border-radius:6px;display:flex;flex-direction:column;gap:4px;'
			}, [
				E('span', { 'style': 'font-size:12px;color:var(--mm-text-secondary);' }, item[0]),
				E('div', { 'style': 'font-size:13px;font-weight:600;word-break:break-all;color:var(--mm-text-primary);' }, [ item[1] ])
			]);
		}));

		return E('div', {}, [ topBar, infoGrid ]);
	},

	renderSmsTab: function() {
		var self = this;

		var tbody = E('tbody');
		var selectAllCb = E('input', { 'type': 'checkbox' });
		var deleteBtn = E('button', {
			'class': 'btn cbi-button-negative',
			'click': ui.createHandlerFn(self, function() {
				var selectedIds = Object.keys(self.selectedSms).filter(function(k) { return self.selectedSms[k]; });
				return self.handleDeleteSms(selectedIds);
			})
		});
		var clearAllBtn = E('button', {
			'class': 'btn cbi-button-negative',
			'click': function() { self.handleDeleteAllSms(); }
		}, _('清空全部短信'));

		var updateSmsTable = function() {
			var filtered = self.cachedSms.filter(function(msg) {
				if (self.smsFilter !== 'all' && (msg.state || '').toLowerCase() !== self.smsFilter) {
					return false;
				}
				if (self.smsSearch) {
					var q = self.smsSearch.toLowerCase();
					var numMatch = (msg.number || '').toLowerCase().indexOf(q) !== -1;
					var txtMatch = (msg.text || '').toLowerCase().indexOf(q) !== -1;
					if (!numMatch && !txtMatch) return false;
				}
				return true;
			});

			var selectedIds = Object.keys(self.selectedSms).filter(function(k) { return self.selectedSms[k]; });
			deleteBtn.textContent = _('删除选中') + ' (' + selectedIds.length + ')';
			if (selectedIds.length === 0) {
				deleteBtn.setAttribute('disabled', 'disabled');
			} else {
				deleteBtn.removeAttribute('disabled');
			}

			if (self.cachedSms.length === 0) {
				clearAllBtn.setAttribute('disabled', 'disabled');
			} else {
				clearAllBtn.removeAttribute('disabled');
			}

			selectAllCb.checked = (filtered.length > 0 && filtered.every(function(m) { return !!self.selectedSms[m.id]; }));

			var tableRows = filtered.map(function(msg) {
				var cb = E('input', {
					'type': 'checkbox',
					'checked': self.selectedSms[msg.id] ? 'checked' : null,
					'change': function(ev) {
						if (ev.target.checked) self.selectedSms[msg.id] = true;
						else delete self.selectedSms[msg.id];
						updateSmsTable();
					}
				});

				return E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'style': 'width:36px;text-align:center;' }, [ cb ]),
					E('td', { 'class': 'td', 'style': 'width:60px;font-weight:600;' }, '#' + msg.id),
					E('td', { 'class': 'td', 'style': 'width:140px;' }, [
						self.formatSmsStateBadge(msg.state),
						E('div', { 'style': 'font-size:11px;color:var(--mm-text-secondary);margin-top:2px;' }, self.formatStorageName(msg.storage))
					]),
					E('td', { 'class': 'td', 'style': 'width:150px;font-weight:600;' }, msg.number || _('未知号码')),
					E('td', { 'class': 'td', 'style': 'width:165px;font-size:12px;color:var(--mm-text-secondary);' }, cleanTimestamp(msg.timestamp)),
					E('td', { 'class': 'td', 'style': 'white-space:pre-wrap;word-break:break-word;min-width:240px;line-height:1.5;' }, msg.text || _('(无文本内容)')),
					E('td', { 'class': 'td', 'style': 'width:150px;text-align:right;white-space:nowrap;' }, [
						E('button', {
							'class': 'btn cbi-button-action',
							'style': 'margin-right:6px;',
							'click': function() {
								self.openSendSmsModal(msg.number !== '未知号码' ? msg.number : '');
							}
						}, _('回复')),
						E('button', {
							'class': 'btn cbi-button-negative',
							'click': ui.createHandlerFn(self, function() {
								return self.handleDeleteSms([ msg.id ]);
							})
						}, _('删除'))
					])
				]);
			});

			if (tableRows.length === 0) {
				tableRows.push(E('tr', { 'class': 'tr placeholder' }, [
					E('td', { 'class': 'td', 'colspan': '7', 'style': 'text-align:center;padding:24px;color:var(--mm-text-secondary);' },
						_('当前没有符合条件的短信记录'))
				]));
			}

			dom.content(tbody, tableRows);
		};

		var filterSelect = E('select', {
			'class': 'cbi-input-select',
			'style': 'width:165px;',
			'change': function(ev) {
				self.smsFilter = ev.target.value;
				updateSmsTable();
			}
		}, [
			E('option', { 'value': 'all', 'selected': self.smsFilter === 'all' ? 'selected' : null }, _('全部短信') + ' (' + self.cachedSms.length + ')'),
			E('option', { 'value': 'received', 'selected': self.smsFilter === 'received' ? 'selected' : null }, _('收件箱 (已接收)')),
			E('option', { 'value': 'sent', 'selected': self.smsFilter === 'sent' ? 'selected' : null }, _('已发送短信')),
			E('option', { 'value': 'stored', 'selected': self.smsFilter === 'stored' ? 'selected' : null }, _('草稿与本地存储'))
		]);

		var searchInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:230px;',
			'placeholder': _('搜索电话号码或中文短信内容...'),
			'value': self.smsSearch,
			'input': function(ev) {
				self.smsSearch = ev.target.value;
				updateSmsTable();
			}
		});

		var toolbar = E('div', {
			'style': 'display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:10px;margin-bottom:12px;'
		}, [
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;' }, [
				filterSelect,
				searchInput
			]),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;' }, [
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': function() { self.openSendSmsModal(''); }
				}, _('发送新短信')),
				deleteBtn,
				clearAllBtn
			])
		]);

		selectAllCb.addEventListener('change', function(ev) {
			var filtered = self.cachedSms.filter(function(msg) {
				if (self.smsFilter !== 'all' && (msg.state || '').toLowerCase() !== self.smsFilter) return false;
				if (self.smsSearch) {
					var q = self.smsSearch.toLowerCase();
					if ((msg.number || '').toLowerCase().indexOf(q) === -1 && (msg.text || '').toLowerCase().indexOf(q) === -1) return false;
				}
				return true;
			});
			filtered.forEach(function(m) {
				if (ev.target.checked) self.selectedSms[m.id] = true;
				else delete self.selectedSms[m.id];
			});
			updateSmsTable();
		});

		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('thead', {}, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th', 'style': 'width:36px;text-align:center;' }, [ selectAllCb ]),
					E('th', { 'class': 'th', 'style': 'width:60px;' }, _('编号')),
					E('th', { 'class': 'th', 'style': 'width:140px;' }, _('状态 / 存储位置')),
					E('th', { 'class': 'th', 'style': 'width:150px;' }, _('对方号码')),
					E('th', { 'class': 'th', 'style': 'width:165px;' }, _('接收 / 发送时间')),
					E('th', { 'class': 'th' }, _('短信正文内容')),
					E('th', { 'class': 'th', 'style': 'width:150px;text-align:right;' }, _('操作'))
				])
			]),
		tbody
		]);

		self.updateSmsTableFn = updateSmsTable;
		updateSmsTable();

		return E('div', {}, [ toolbar, table ]);
	},

	renderCallsTab: function() {
		var self = this;

		var tbody = E('tbody');
		var selectAllCb = E('input', { 'type': 'checkbox' });
		var deleteBtn = E('button', {
			'class': 'btn cbi-button-negative',
			'click': ui.createHandlerFn(self, function() {
				var selectedIds = Object.keys(self.selectedCalls).filter(function(k) { return self.selectedCalls[k]; });
				return self.handleDeleteCall(selectedIds);
			})
		});
		var clearAllBtn = E('button', {
			'class': 'btn cbi-button-negative',
			'click': function() { self.handleDeleteAllCalls(); }
		}, _('清空全部通话记录'));

		var updateCallsTable = function() {
			var filtered = self.cachedCalls.filter(function(c) {
				var dir = (c.direction || '').toLowerCase();
				var st = (c.state || '').toLowerCase();
				if (self.callFilter === 'incoming' && dir !== 'incoming') return false;
				if (self.callFilter === 'outgoing' && dir !== 'outgoing') return false;
				if (self.callFilter === 'active' && st === 'terminated') return false;
				if (self.callSearch) {
					var q = self.callSearch.toLowerCase();
					if ((c.number || '').toLowerCase().indexOf(q) === -1) return false;
				}
				return true;
			});

			var selectedIds = Object.keys(self.selectedCalls).filter(function(k) { return self.selectedCalls[k]; });
			deleteBtn.textContent = _('删除选中') + ' (' + selectedIds.length + ')';
			if (selectedIds.length === 0) {
				deleteBtn.setAttribute('disabled', 'disabled');
			} else {
				deleteBtn.removeAttribute('disabled');
			}

			if (self.cachedCalls.length === 0) {
				clearAllBtn.setAttribute('disabled', 'disabled');
			} else {
				clearAllBtn.removeAttribute('disabled');
			}

			selectAllCb.checked = (filtered.length > 0 && filtered.every(function(c) { return !!self.selectedCalls[c.id]; }));

			var tableRows = filtered.map(function(c) {
				var cb = E('input', {
					'type': 'checkbox',
					'checked': self.selectedCalls[c.id] ? 'checked' : null,
					'change': function(ev) {
						if (ev.target.checked) self.selectedCalls[c.id] = true;
						else delete self.selectedCalls[c.id];
						updateCallsTable();
					}
				});

				var st = (c.state || '').toLowerCase();
				var actionBtns = [];

				if (st === 'ringing-in' || st === 'waiting') {
					actionBtns.push(E('button', {
						'class': 'btn cbi-button-positive',
						'style': 'margin-right:4px;',
						'click': ui.createHandlerFn(self, function() {
							return callCallAction(self.currentModem, c.id, 'accept').then(function(res) {
								if (!res || typeof res.code !== 'number') {
									return runForwarderDirect([ '--db-call-action', self.currentModem, c.id, 'accept' ]);
								}
							}).then(function() {
								return self.refreshData();
							});
						})
					}, _('接听')));
				}

				if (st !== 'terminated' && st !== 'unknown') {
					actionBtns.push(E('button', {
						'class': 'btn cbi-button-negative',
						'style': 'margin-right:4px;',
						'click': ui.createHandlerFn(self, function() {
							return callCallAction(self.currentModem, c.id, 'hangup').then(function(res) {
								if (!res || typeof res.code !== 'number') {
									return runForwarderDirect([ '--db-call-action', self.currentModem, c.id, 'hangup' ]);
								}
							}).then(function() {
								return self.refreshData();
							});
						})
					}, _('挂断')));
				}

				actionBtns.push(E('button', {
					'class': 'btn cbi-button-action',
					'style': 'margin-right:4px;',
					'click': function() {
						self.openDialModal(c.number !== '未知号码' ? c.number : '');
					}
				}, _('回拨')));

				actionBtns.push(E('button', {
					'class': 'btn',
					'style': 'margin-right:4px;',
					'click': function() {
						self.openSendSmsModal(c.number !== '未知号码' ? c.number : '');
					}
				}, _('发短信')));

				actionBtns.push(E('button', {
					'class': 'btn cbi-button-negative',
					'click': ui.createHandlerFn(self, function() {
						return self.handleDeleteCall([ c.id ]);
					})
				}, _('删除记录')));

				var displayTime = getLocalCallTimestamp(self.currentModem, c.id, c.number, c.timestamp);

				return E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td', 'style': 'width:36px;text-align:center;' }, [ cb ]),
					E('td', { 'class': 'td', 'style': 'width:60px;font-weight:600;' }, '#' + c.id),
					E('td', { 'class': 'td', 'style': 'width:130px;' }, [ self.formatCallDirectionBadge(c.direction) ]),
					E('td', { 'class': 'td', 'style': 'width:150px;font-weight:600;' }, c.number || _('未知号码')),
					E('td', { 'class': 'td', 'style': 'width:135px;' }, [ self.formatCallStateBadge(c.state) ]),
					E('td', { 'class': 'td', 'style': 'width:155px;font-size:12px;color:var(--mm-text-secondary);' }, self.formatCallReason(c.state_reason, c.direction, c.state)),
					E('td', { 'class': 'td', 'style': 'width:165px;font-size:12px;color:var(--mm-text-secondary);' }, displayTime),
					E('td', { 'class': 'td', 'style': 'text-align:right;white-space:nowrap;' }, actionBtns)
				]);
			});

			if (tableRows.length === 0) {
				tableRows.push(E('tr', { 'class': 'tr placeholder' }, [
					E('td', { 'class': 'td', 'colspan': '8', 'style': 'text-align:center;padding:24px;color:var(--mm-text-secondary);' },
						_('当前没有符合条件的通话记录'))
				]));
			}

			dom.content(tbody, tableRows);
		};

		var filterSelect = E('select', {
			'class': 'cbi-input-select',
			'style': 'width:165px;',
			'change': function(ev) {
				self.callFilter = ev.target.value;
				updateCallsTable();
			}
		}, [
			E('option', { 'value': 'all', 'selected': self.callFilter === 'all' ? 'selected' : null }, _('全部通话记录') + ' (' + self.cachedCalls.length + ')'),
			E('option', { 'value': 'incoming', 'selected': self.callFilter === 'incoming' ? 'selected' : null }, _('呼入来电记录')),
			E('option', { 'value': 'outgoing', 'selected': self.callFilter === 'outgoing' ? 'selected' : null }, _('呼出去电记录')),
			E('option', { 'value': 'active', 'selected': self.callFilter === 'active' ? 'selected' : null }, _('当前正在通话 / 振铃'))
		]);

		var searchInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:220px;',
			'placeholder': _('按电话号码筛选通话记录...'),
			'value': self.callSearch,
			'input': function(ev) {
				self.callSearch = ev.target.value;
				updateCallsTable();
			}
		});

		var toolbar = E('div', {
			'style': 'display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:10px;margin-bottom:12px;'
		}, [
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;' }, [
				filterSelect,
				searchInput
			]),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;' }, [
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': function() { self.openDialModal(''); }
				}, _('拨号呼叫')),
				deleteBtn,
				clearAllBtn
			])
		]);

		selectAllCb.addEventListener('change', function(ev) {
			var filtered = self.cachedCalls.filter(function(c) {
				var dir = (c.direction || '').toLowerCase();
				var st = (c.state || '').toLowerCase();
				if (self.callFilter === 'incoming' && dir !== 'incoming') return false;
				if (self.callFilter === 'outgoing' && dir !== 'outgoing') return false;
				if (self.callFilter === 'active' && st === 'terminated') return false;
				if (self.callSearch) {
					var q = self.callSearch.toLowerCase();
					if ((c.number || '').toLowerCase().indexOf(q) === -1) return false;
				}
				return true;
			});
			filtered.forEach(function(c) {
				if (ev.target.checked) self.selectedCalls[c.id] = true;
				else delete self.selectedCalls[c.id];
			});
			updateCallsTable();
		});

		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('thead', {}, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th', 'style': 'width:36px;text-align:center;' }, [ selectAllCb ]),
					E('th', { 'class': 'th', 'style': 'width:60px;' }, _('编号')),
					E('th', { 'class': 'th', 'style': 'width:130px;' }, _('呼叫方向')),
					E('th', { 'class': 'th', 'style': 'width:150px;' }, _('对方号码')),
					E('th', { 'class': 'th', 'style': 'width:135px;' }, _('通话状态')),
					E('th', { 'class': 'th', 'style': 'width:155px;' }, _('状态说明')),
					E('th', { 'class': 'th', 'style': 'width:165px;' }, _('来电 / 通话时间')),
					E('th', { 'class': 'th', 'style': 'text-align:right;' }, _('操作'))
				])
			]),
		tbody
		]);

		self.updateCallsTableFn = updateCallsTable;
		updateCallsTable();

		return E('div', {}, [ toolbar, table ]);
	},

	renderControlTab: function() {
		var self = this;
		var ussdInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'width:240px;margin-right:8px;',
			'placeholder': _('例如：*101# 或 *102#')
		});
		var ussdOutput = E('pre', {
			'style': 'margin-top:10px;padding:12px;background:#1f2328;color:#f0f6fc;border-radius:6px;min-height:60px;white-space:pre-wrap;font-size:12px;'
		}, _('USSD 响应结果将显示在此处（支持 UCS-2 中文自动解码）...'));

		var runModemFlag = function(action, flag, msgText) {
			return callModemAction(self.currentModem, action).then(function(res) {
				if (res && typeof res.code === 'number') {
					ui.addNotification(null, E('p', res.output || msgText), 'info');
					return self.refreshData();
				}
				return runMmcliDirect([ '-m', self.currentModem, flag ]).then(function(dres) {
					ui.addNotification(null, E('p', dres.stdout || dres.stderr || msgText), 'info');
					return self.refreshData();
				});
			});
		};

		return E('div', { 'style': 'display:flex;flex-direction:column;gap:16px;' }, [
			E('div', { 'class': 'cbi-section', 'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);' }, [
				E('h4', { 'style': 'margin-top:0;' }, _('模块电源与连接状态控制')),
				E('p', { 'style': 'color:var(--mm-text-secondary);font-size:13px;' }, _('通过 ModemManager (mmcli) 控制当前蜂窝模块的启用、低功耗禁用与软重启。')),
				E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:10px;' }, [
					E('button', {
						'class': 'btn cbi-button-positive',
						'click': ui.createHandlerFn(self, function() {
							return runModemFlag('enable', '-e', _('模块已启用'));
						})
					}, _('启用模块 (-e)')),
					E('button', {
						'class': 'btn cbi-button-neutral',
						'click': ui.createHandlerFn(self, function() {
							return runModemFlag('disable', '-d', _('模块已禁用'));
						})
					}, _('禁用模块 (-d)')),
					E('button', {
						'class': 'btn cbi-button-negative',
						'click': ui.createHandlerFn(self, function() {
							return runModemFlag('reset', '-r', _('已发送模块重启指令'));
						})
					}, _('重启模块 (-r)'))
				])
			]),
			E('div', { 'class': 'cbi-section', 'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);' }, [
				E('h4', { 'style': 'margin-top:0;' }, _('3GPP USSD 快捷指令查询')),
				E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;' }, [
					ussdInput,
					E('button', {
						'class': 'btn cbi-button-action important',
						'click': ui.createHandlerFn(self, function() {
							var code = (ussdInput.value || '').trim();
							return callUssdQuery(self.currentModem, code, 'initiate').then(function(res) {
								if (res && (res.output || res.error)) {
									ussdOutput.textContent = res.output || res.error;
									return;
								}
								return runMmcliDirect([ '-m', self.currentModem, '--3gpp-ussd-initiate=' + code ]).then(function(dres) {
									ussdOutput.textContent = dres.stdout || dres.stderr || _('无响应输出');
								});
							});
						})
					}, _('发送 USSD 指令')),
					E('button', {
						'class': 'btn',
						'click': ui.createHandlerFn(self, function() {
							var code = (ussdInput.value || '').trim();
							return callUssdQuery(self.currentModem, code, 'respond').then(function(res) {
								if (res && (res.output || res.error)) {
									ussdOutput.textContent = res.output || res.error;
									return;
								}
								return runMmcliDirect([ '-m', self.currentModem, '--3gpp-ussd-respond=' + code ]).then(function(dres) {
									ussdOutput.textContent = dres.stdout || dres.stderr || _('无响应输出');
								});
							});
						})
					}, _('回复交互菜单')),
					E('button', {
						'class': 'btn cbi-button-negative',
						'click': ui.createHandlerFn(self, function() {
							return callUssdQuery(self.currentModem, '', 'cancel').then(function(res) {
								if (res && (res.output || res.error)) {
									ussdOutput.textContent = res.output || res.error;
									return;
								}
								return runMmcliDirect([ '-m', self.currentModem, '--3gpp-ussd-cancel' ]).then(function(dres) {
									ussdOutput.textContent = dres.stdout || dres.stderr || _('会话已取消');
								});
							});
						})
					}, _('取消 USSD 会话'))
				]),
				ussdOutput
			])
		]);
	},

	renderAtTab: function() {
		var self = this;
		var st = (self.cachedStatus && self.cachedStatus.status) ? self.cachedStatus.status : {};
		var portsInfo = st.ports || st.primary_port || 'cdc-wdm0';
		var presetsList = (Array.isArray(self.atPresets) && self.atPresets.length > 0) ? self.atPresets : DEFAULT_AT_PRESETS;

		var cmdInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'style': 'flex:1;min-width:180px;font-family:monospace;font-weight:600;',
			'placeholder': _('输入 AT 命令，例如 ATI、AT+CSQ、AT+GTCCINFO? ...'),
			'value': self.atCommandInput || 'ATI',
			'input': function(ev) {
				self.atCommandInput = ev.target.value;
			},
			'keydown': function(ev) {
				if (ev.key === 'Enter') {
					ev.preventDefault();
					self.executeAtCommand(cmdInput.value);
				}
			}
		});

		var presetSelect = E('select', {
			'class': 'cbi-input-select',
			'style': 'min-width:260px;max-width:360px;',
			'change': function(ev) {
				var val = ev.target.value;
				if (val) {
					self.atCommandInput = val;
					cmdInput.value = val;
				}
			}
		}, [
			E('option', { 'value': '' }, _('-- 选择快捷 AT 指令（' + presetsList.length + ' 条） --'))
		].concat(presetsList.map(function(p) {
			return E('option', {
				'value': p.cmd,
				'selected': (self.atCommandInput === p.cmd) ? 'selected' : null
			}, p.desc || p.cmd);
		})));

		var quickButtons = presetsList.slice(0, 16).map(function(p) {
			return E('button', {
				'class': 'btn',
				'style': 'font-family:monospace;font-size:12px;padding:3px 8px;',
				'title': p.desc || p.cmd,
				'click': ui.createHandlerFn(self, function() {
					self.atCommandInput = p.cmd;
					cmdInput.value = p.cmd;
					return self.executeAtCommand(p.cmd);
				})
			}, p.cmd);
		});

		var clearLogBtn = E('button', {
			'class': 'btn cbi-button-negative',
			'style': 'flex-shrink:0;white-space:nowrap;min-width:90px;',
			'disabled': self.atLogHistory.length === 0 ? 'disabled' : null,
			'click': function() {
				self.atLogHistory = [];
				if (self.atLogPreNode) {
					self.atLogPreNode.textContent = self.formatAtLogText();
				}
				clearLogBtn.setAttribute('disabled', 'disabled');
			}
		}, _('清空记录'));
		self.atClearLogBtnNode = clearLogBtn;

		var sendBtn = E('button', {
			'class': 'btn cbi-button-action important',
			'style': 'flex-shrink:0;white-space:nowrap;min-width:115px;',
			'click': ui.createHandlerFn(self, function() {
				return self.executeAtCommand(cmdInput.value);
			})
		}, _('发送 AT 命令'));

		var bookmarkBtn = E('button', {
			'class': 'btn',
			'style': 'flex-shrink:0;white-space:nowrap;min-width:80px;',
			'title': _('将当前输入框内的 AT 命令添加到快捷库'),
			'click': function() { self.openAddPresetModal(cmdInput.value); }
		}, _('收藏'));

		var logPre = E('pre', {
			'style': 'margin:0;padding:14px;background:#0d1117;color:#58a6ff;border-radius:8px;min-height:220px;max-height:460px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;font-family:monospace;font-size:13px;line-height:1.5;'
		}, self.formatAtLogText());
		self.atLogPreNode = logPre;

		return E('div', { 'style': 'display:flex;flex-direction:column;gap:14px;' }, [
			E('div', {
				'class': 'cbi-section',
				'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);'
			}, [
				E('div', { 'style': 'display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:8px;margin-bottom:8px;' }, [
					E('h4', { 'style': 'margin:0;' }, _('ModemManager 原生 AT 命令交互终端')),
					E('span', { 'style': 'font-size:12px;color:var(--mm-text-secondary);' }, _('当前模块通信端口：') + portsInfo)
				]),
				E('p', { 'style': 'color:var(--mm-text-secondary);font-size:12px;margin-top:0;margin-bottom:10px;' },
					_('基于 ModemManager 原生接口 (mmcli -m ') + self.currentModem + _(' --command="<AT>") 发送指令。支持自定义添加、编辑与删除指令库。ModemManager 默认要求开启 --debug 调试模式才允许透传 AT 命令（插件已自动配置）。')),

				// Row 1: Preset selection & configuration tools
				E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:10px;' }, [
					E('label', { 'style': 'font-size:12px;font-weight:600;color:var(--mm-text-secondary);' }, _('常用指令库：')),
					presetSelect,
					E('button', {
						'class': 'btn cbi-button-neutral',
						'title': _('自定义添加、修改或删除常用 AT 指令库'),
						'click': function() { self.openManageAtPresetsModal(); }
					}, _('管理指令库')),
					E('button', {
						'class': 'btn',
						'click': ui.createHandlerFn(self, function() {
							return callEnableAtDebug().catch(function() {
								return null;
							}).then(function(res) {
								if (res && typeof res.code === 'number') {
									ui.addNotification(null, E('p', res.output || _('已开启 ModemManager AT 调试模式')), 'info');
									return;
								}
								return fs.exec('/usr/bin/modemmanager-enable-at', []).then(function(dres) {
									ui.addNotification(null, E('p', (dres && dres.stdout) ? dres.stdout : _('已开启 ModemManager AT 调试模式')), 'info');
								});
							});
						})
					}, _('开启/修复 AT 调试模式'))
				]),

				// Row 2: Fixed single-line execution row (Never wraps, so cmdInput width is strictly stable and never flickers!)
				E('div', { 'style': 'display:flex;align-items:center;gap:8px;margin-bottom:12px;' }, [
					cmdInput,
					sendBtn,
					bookmarkBtn,
					clearLogBtn
				]),

				// Row 3: Quick command buttons
				E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin-bottom:12px;' }, [
					E('span', { 'style': 'font-size:12px;color:var(--mm-text-secondary);font-weight:600;' }, _('快捷指令一键发送：'))
				].concat(quickButtons).concat([
					E('button', {
						'class': 'btn',
						'style': 'font-size:11px;padding:3px 8px;color:var(--mm-accent);',
						'click': function() { self.openManageAtPresetsModal(); }
					}, _('管理更多...'))
				])),

				// Row 4: Terminal output pre
				logPre
			])
		]);
	},

	renderForwardTab: function() {
		var self = this;
		var cfg = self.forwardConfig || defaultForwardConfig();
		var ch = cfg.channels;

		var statusBadge = E('span', {
			'style': 'display:inline-block;padding:2px 10px;border-radius:12px;font-size:12px;font-weight:600;color:#fff;background:' +
				(self.forwardRunning ? '#2ea043' : '#6e7781')
		}, self.forwardRunning ? _('后台守护进程运行中') : _('后台守护进程未运行'));
		self.forwardStatusBadgeNode = statusBadge;

		var logPre = E('pre', {
			'style': 'margin:0;padding:12px;background:#0d1117;color:#a5d6ff;border-radius:6px;min-height:140px;max-height:280px;overflow-y:auto;white-space:pre-wrap;word-break:break-all;font-family:monospace;font-size:12px;line-height:1.5;'
		}, self.forwardLogs || _('暂无短信转发日志...'));
		self.forwardLogPreNode = logPre;

		var refreshLogsOnly = function() {
			return self.refreshForwardStatusAndLogs();
		};

		var runTest = function(channelKey, labelName) {
			ui.addNotification(null, E('p', _('正在向 ') + labelName + _(' 发送测试通知...')), 'info');
			return callTestForward(channelKey, cfg).catch(function() { return {}; }).then(function(res) {
				if (res && Array.isArray(res.results)) return res;
				return runForwarderDirect([ '--test', channelKey, JSON.stringify(cfg) ]).then(function(dres) {
					if (dres && Array.isArray(dres.results)) {
						return { code: dres.any_ok ? 0 : 1, results: dres.results };
					}
					return dres || {};
				});
			}).then(function(res) {
				if (res && res.code === 0) {
					cfg.enabled = true;
					if (channelKey !== 'all' && cfg.channels && cfg.channels[channelKey]) {
						cfg.channels[channelKey].enabled = true;
					}
					self.updateContainers();
				}
				refreshLogsOnly();
				if (res && Array.isArray(res.results) && res.results.length > 0) {
					var msgs = res.results.map(function(r) {
						return r.label + ': ' + (r.ok ? '发送成功 (已自动保存并启用该渠道)' : ('失败 (' + (r.error || '未知错误') + ')'));
					});
					ui.addNotification(null, E('p', msgs.join(' | ')), res.code === 0 ? 'info' : 'danger');
				} else {
					ui.addNotification(null, E('p', (res && res.error) ? res.error : _('未启用任何转发渠道或配置为空')), 'warning');
				}
			}).catch(function(err) {
				ui.addNotification(null, E('p', _('测试调用失败: ') + err), 'danger');
			});
		};

		var mkRow = function(labelText, inputNode, hintText) {
			return E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:8px;' }, [
				E('label', { 'style': 'width:135px;font-size:12px;font-weight:600;color:var(--mm-text-primary);' }, labelText),
				E('div', { 'style': 'flex:1;min-width:220px;display:flex;flex-direction:column;gap:2px;' }, [
					inputNode,
					hintText ? E('span', { 'style': 'font-size:11px;color:var(--mm-text-secondary);' }, hintText) : ''
				])
			]);
		};

		var mkCheckbox = function(checked, labelText, onChange) {
			var cb = E('input', {
				'type': 'checkbox',
				'checked': checked ? 'checked' : null,
				'style': 'margin-right:6px;',
				'change': function(ev) { onChange(!!ev.target.checked); }
			});
			return E('label', { 'style': 'display:inline-flex;align-items:center;cursor:pointer;font-size:13px;font-weight:600;margin-right:16px;color:var(--mm-text-primary);' }, [ cb, labelText ]);
		};

		// Global settings card
		var deviceInput = E('input', {
			'type': 'text', 'class': 'cbi-input-text', 'style': 'width:180px;',
			'value': cfg.device_tag || 'OpenWrt',
			'input': function(ev) { cfg.device_tag = ev.target.value; }
		});
		var intervalInput = E('input', {
			'type': 'number', 'class': 'cbi-input-text', 'style': 'width:80px;',
			'min': '2', 'max': '60', 'value': '' + (cfg.poll_interval || 5),
			'input': function(ev) { cfg.poll_interval = parseInt(ev.target.value, 10) || 5; }
		});

		var globalCard = E('div', { 'class': 'cbi-section', 'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);' }, [
			E('div', { 'style': 'display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:10px;margin-bottom:12px;' }, [
				E('div', { 'style': 'display:flex;align-items:center;gap:10px;' }, [
					E('h4', { 'style': 'margin:0;' }, _('短信自动转发总控设置')),
					statusBadge
				]),
				E('div', { 'style': 'display:flex;flex-wrap:wrap;gap:8px;' }, [
					E('button', {
						'class': 'btn cbi-button-action important',
						'click': ui.createHandlerFn(self, function() {
							return callSaveForwardConfig(cfg).catch(function() { return {}; }).then(function(res) {
								if (res && typeof res.running === 'boolean') return res;
								return runForwarderDirect([ '--save', JSON.stringify(cfg) ]);
							}).then(function(res) {
								self.forwardRunning = !!(res && res.running);
								self.updateForwardBadgeNode();
								refreshLogsOnly();
								ui.addNotification(null, E('p', (res && res.message) ? res.message : _('短信转发配置已保存并生效')), 'info');
							});
						})
					}, _('保存并应用配置')),
					E('button', {
						'class': 'btn',
						'click': ui.createHandlerFn(self, function() {
							return runTest('all', _('所有已启用渠道'));
						})
					}, _('一键测试已启用渠道')),
					E('button', {
						'class': 'btn cbi-button-positive',
						'title': _('立即读取模块收件箱中最新一条真实短信并推送到所有已启用渠道'),
						'click': ui.createHandlerFn(self, function() {
							return callForwardLatest(cfg).catch(function() { return {}; }).then(function(res) {
								if (res && Array.isArray(res.results) && res.results.length > 0) return res;
								return runForwarderDirect([ '--forward-latest', JSON.stringify(cfg) ]).then(function(dres) {
									if (dres && Array.isArray(dres.results)) {
										return { code: dres.any_ok ? 0 : 1, results: dres.results, error: dres.error || '' };
									}
									return dres || {};
								});
							}).then(function(res) {
								refreshLogsOnly();
								if (res && Array.isArray(res.results) && res.results.length > 0) {
									var msgs = res.results.map(function(r) {
										return r.label + ': ' + (r.ok ? '真实短信转发成功' : ('失败 (' + (r.error || '未知错误') + ')'));
									});
									ui.addNotification(null, E('p', msgs.join(' | ')), res.code === 0 ? 'info' : 'danger');
								} else {
									ui.addNotification(null, E('p', (res && res.error) ? res.error : _('请先勾选至少一个推送渠道（如 Telegram 或 Bark）')), 'warning');
								}
							});
						})
					}, _('转发最新一条真实短信'))
				])
			]),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:12px;margin-bottom:10px;' }, [
				mkCheckbox(cfg.enabled, _('启用后台自动转发'), function(v) { cfg.enabled = v; }),
				mkCheckbox(cfg.forward_calls, _('同时转发来电提醒'), function(v) { cfg.forward_calls = v; }),
				mkCheckbox(cfg.delete_after_forward, _('转发成功后同时从本地数据库删除 (模块内短信已默认自动清空)'), function(v) { cfg.delete_after_forward = v; })
			]),
			E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:16px;' }, [
				E('div', { 'style': 'display:flex;align-items:center;gap:6px;' }, [
					E('span', { 'style': 'font-size:12px;font-weight:600;color:var(--mm-text-secondary);' }, _('设备标识名称：')),
					deviceInput
				]),
				E('div', { 'style': 'display:flex;align-items:center;gap:6px;' }, [
					E('span', { 'style': 'font-size:12px;font-weight:600;color:var(--mm-text-secondary);' }, _('后台检测间隔（秒）：')),
					intervalInput
				])
			])
		]);

		// Telegram Card
		var tgCard = E('div', { 'class': 'cbi-section', 'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);' }, [
			E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;' }, [
				mkCheckbox(ch.telegram.enabled, 'Telegram 机器人推送', function(v) { ch.telegram.enabled = v; }),
				E('button', {
					'class': 'btn',
					'click': ui.createHandlerFn(self, function() { return runTest('telegram', 'Telegram'); })
				}, _('测试 Telegram'))
			]),
			mkRow(_('Bot Token：'), E('input', {
				'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
				'placeholder': '例如：123456789:ABCDefGhIJKlmNoPQRsTUVwxyZ',
				'value': ch.telegram.bot_token || '',
				'input': function(ev) { ch.telegram.bot_token = ev.target.value; }
			}), _('从 @BotFather 获取的机器人 Token')),
			mkRow(_('Chat ID：'), E('input', {
				'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
				'placeholder': '例如：123456789 或群组 ID (-100...)',
				'value': ch.telegram.chat_id || '',
				'input': function(ev) { ch.telegram.chat_id = ev.target.value; }
			}), _('接收消息的个人或群组 Chat ID')),
			mkRow(_('API 接口地址：'), E('input', {
				'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
				'placeholder': 'https://api.telegram.org',
				'value': ch.telegram.api_host || 'https://api.telegram.org',
				'input': function(ev) { ch.telegram.api_host = ev.target.value; }
			}), _('默认 https://api.telegram.org；国内直连可填写 Cloudflare Workers 等反代地址'))
		]);

		// Bark Card
		var barkCard = E('div', { 'class': 'cbi-section', 'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);' }, [
			E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;' }, [
				mkCheckbox(ch.bark.enabled, 'Bark 推送 (iPhone / iPad)', function(v) { ch.bark.enabled = v; }),
				E('button', {
					'class': 'btn',
					'click': ui.createHandlerFn(self, function() { return runTest('bark', 'Bark'); })
				}, _('测试 Bark'))
			]),
			mkRow(_('Bark 服务器地址：'), E('input', {
				'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
				'placeholder': 'https://api.day.app',
				'value': ch.bark.server_url || 'https://api.day.app',
				'input': function(ev) { ch.bark.server_url = ev.target.value; }
			}), _('官方默认 https://api.day.app，或填写自建 Bark 服务端地址')),
			mkRow(_('Device Key：'), E('input', {
				'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
				'placeholder': '从 Bark App 首页复制的 22 位设备 Key',
				'value': ch.bark.device_key || '',
				'input': function(ev) { ch.bark.device_key = ev.target.value; }
			}), ''),
			mkRow(_('推送分组 / 铃声：'), E('div', { 'style': 'display:flex;gap:8px;' }, [
				E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'style': 'flex:1;',
					'placeholder': '分组名，例如 OpenWrt短信',
					'value': ch.bark.group || 'OpenWrt短信',
					'input': function(ev) { ch.bark.group = ev.target.value; }
				}),
				E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'style': 'flex:1;',
					'placeholder': '铃声名（可选，如 minuet、bell）',
					'value': ch.bark.sound || '',
					'input': function(ev) { ch.bark.sound = ev.target.value; }
				})
			]), '')
		]);

		// Other channels card (WeCom, DingTalk, Feishu, ServerChan, Custom Webhook)
		var otherCard = E('div', { 'class': 'cbi-section', 'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);' }, [
			E('h4', { 'style': 'margin-top:0;margin-bottom:12px;' }, _('其他推送渠道（企业微信 / 钉钉 / 飞书 / Server酱 / Webhook）')),

			E('div', { 'style': 'padding-bottom:10px;margin-bottom:10px;border-bottom:1px solid var(--mm-border-subtle);' }, [
				E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;' }, [
					mkCheckbox(ch.wecom.enabled, '企业微信群机器人', function(v) { ch.wecom.enabled = v; }),
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(self, function() { return runTest('wecom', '企业微信'); }) }, _('测试企业微信'))
				]),
				mkRow(_('Webhook URL：'), E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
					'placeholder': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=...',
					'value': ch.wecom.webhook_url || '',
					'input': function(ev) { ch.wecom.webhook_url = ev.target.value; }
				}), '')
			]),

			E('div', { 'style': 'padding-bottom:10px;margin-bottom:10px;border-bottom:1px solid var(--mm-border-subtle);' }, [
				E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;' }, [
					mkCheckbox(ch.dingtalk.enabled, '钉钉群机器人', function(v) { ch.dingtalk.enabled = v; }),
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(self, function() { return runTest('dingtalk', '钉钉'); }) }, _('测试钉钉'))
				]),
				mkRow(_('Webhook URL：'), E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
					'placeholder': 'https://oapi.dingtalk.com/robot/send?access_token=...',
					'value': ch.dingtalk.webhook_url || '',
					'input': function(ev) { ch.dingtalk.webhook_url = ev.target.value; }
				}), _('若开启关键字校验，请将设备标识名称设为包含该关键字'))
			]),

			E('div', { 'style': 'padding-bottom:10px;margin-bottom:10px;border-bottom:1px solid var(--mm-border-subtle);' }, [
				E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;' }, [
					mkCheckbox(ch.feishu.enabled, '飞书群机器人', function(v) { ch.feishu.enabled = v; }),
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(self, function() { return runTest('feishu', '飞书'); }) }, _('测试飞书'))
				]),
				mkRow(_('Webhook URL：'), E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
					'placeholder': 'https://open.feishu.cn/open-apis/bot/v2/hook/...',
					'value': ch.feishu.webhook_url || '',
					'input': function(ev) { ch.feishu.webhook_url = ev.target.value; }
				}), '')
			]),

			E('div', { 'style': 'padding-bottom:10px;margin-bottom:10px;border-bottom:1px solid var(--mm-border-subtle);' }, [
				E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;' }, [
					mkCheckbox(ch.serverchan.enabled, 'Server酱 (微信推送)', function(v) { ch.serverchan.enabled = v; }),
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(self, function() { return runTest('serverchan', 'Server酱'); }) }, _('测试 Server酱'))
				]),
				mkRow(_('SendKey：'), E('input', {
					'type': 'text', 'class': 'cbi-input-text', 'style': 'width:100%;font-family:monospace;',
					'placeholder': 'SCT...',
					'value': ch.serverchan.sendkey || '',
					'input': function(ev) { ch.serverchan.sendkey = ev.target.value; }
				}), '')
			]),

			E('div', {}, [
				E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;' }, [
					mkCheckbox(ch.webhook.enabled, '自定义 Webhook 接口', function(v) { ch.webhook.enabled = v; }),
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(self, function() { return runTest('webhook', '自定义 Webhook'); }) }, _('测试 Webhook'))
				]),
				mkRow(_('请求方式与 URL：'), E('div', { 'style': 'display:flex;gap:8px;' }, [
					E('select', {
						'class': 'cbi-input-select', 'style': 'width:90px;',
						'change': function(ev) { ch.webhook.method = ev.target.value; }
					}, [
						E('option', { 'value': 'POST', 'selected': (ch.webhook.method || 'POST') === 'POST' ? 'selected' : null }, 'POST'),
						E('option', { 'value': 'GET', 'selected': ch.webhook.method === 'GET' ? 'selected' : null }, 'GET')
					]),
					E('input', {
						'type': 'text', 'class': 'cbi-input-text', 'style': 'flex:1;font-family:monospace;',
						'placeholder': 'https://example.com/hook?num={number}&msg={text}',
						'value': ch.webhook.url || '',
						'input': function(ev) { ch.webhook.url = ev.target.value; }
					})
				]), _('POST 自动发送 JSON；GET 支持 URL 占位符 {number} {text} {time} {device}'))
			])
		]);

		// Logs Card
		var logCard = E('div', { 'class': 'cbi-section', 'style': 'padding:14px;border:1px solid var(--mm-border);border-radius:8px;background:var(--mm-card-bg);color:var(--mm-text-primary);box-shadow:var(--mm-shadow);' }, [
			E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;' }, [
				E('h4', { 'style': 'margin:0;' }, _('短信转发运行日志')),
				E('div', { 'style': 'display:flex;gap:8px;' }, [
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(self, refreshLogsOnly) }, _('刷新日志')),
					E('button', {
						'class': 'btn cbi-button-negative',
						'click': ui.createHandlerFn(self, function() {
							return callClearForwardLogs().catch(function() {
								return runForwarderDirect([ '--clear-logs' ]);
							}).then(function() {
								self.forwardLogs = '';
								if (self.forwardLogPreNode) self.forwardLogPreNode.textContent = _('暂无短信转发日志...');
							});
						})
					}, _('清空日志'))
				])
			]),
			logPre
		]);

		return E('div', { 'style': 'display:flex;flex-direction:column;gap:14px;' }, [
			globalCard,
			E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:14px;' }, [
				tgCard,
				barkCard
			]),
			otherCard,
			logCard
		]);
	},

	renderTabsBar: function() {
		var self = this;
		var tabs = [
			{ id: 'sms', label: _('短信管理') + ' (' + self.cachedSms.length + ')' },
			{ id: 'calls', label: _('通话记录') + ' (' + self.cachedCalls.length + ')' },
			{ id: 'forward', label: _('短信转发') },
			{ id: 'control', label: _('模块控制与 USSD') },
			{ id: 'at', label: _('AT 命令') }
		];

		return E('ul', { 'class': 'cbi-tabmenu', 'style': 'margin-bottom:14px;display:flex;flex-wrap:wrap;gap:4px;' }, tabs.map(function(t) {
			var isActive = (self.activeTab === t.id);
			return E('li', {
				'class': isActive ? 'cbi-tab' : 'cbi-tab-disabled',
				'style': 'cursor:pointer;'
			}, [
				E('a', {
					'href': '#',
					'click': function(ev) {
						ev.preventDefault();
						self.activeTab = t.id;
						self.updateContainers();
						self.refreshData(true);
					}
				}, t.label)
			]);
		}));
	},

	updateContainers: function() {
		var self = this;
		ensureMmThemeStyles();
		if (self.statusContainer) {
			dom.content(self.statusContainer, self.renderStatusCard());
		}
		if (self.tabsContainer) {
			dom.content(self.tabsContainer, self.renderTabsBar());
		}
		if (self.bodyContainer) {
			var contentNode = null;
			if (self.activeTab === 'sms') contentNode = self.renderSmsTab();
			else if (self.activeTab === 'calls') contentNode = self.renderCallsTab();
			else if (self.activeTab === 'forward') contentNode = self.renderForwardTab();
			else if (self.activeTab === 'at') contentNode = self.renderAtTab();
			else contentNode = self.renderControlTab();
			dom.content(self.bodyContainer, contentNode);
		}
	},

	render: function(data) {
		var self = this;
		self.cachedStatus = data[0] || { found: false };
		self.cachedSms = (data[1] && Array.isArray(data[1].messages)) ? data[1].messages : [];
		self.cachedCalls = (data[2] && Array.isArray(data[2].calls)) ? data[2].calls : [];

		self.statusContainer = E('div', { 'id': 'mm-status-container' });
		self.tabsContainer = E('div', { 'id': 'mm-tabs-container' });
		self.bodyContainer = E('div', { 'id': 'mm-body-container' });

		self.updateContainers();

		poll.add(function() {
			if (self.atRunning) {
				return Promise.resolve();
			}
			return self.refreshData(true);
		}, 5);

		ensureMmThemeStyles();
		setTimeout(function() { ensureMmThemeStyles(); }, 60);
		return E('div', { 'class': 'cbi-map', 'id': 'mm-root-container' }, [
			E('h2', {}, _('ModemManager 调制解调器管理中心')),
			E('div', { 'class': 'cbi-map-descr', 'style': 'margin-bottom:12px;' },
				_('管理基于 ModemManager (mmcli) 的 3G/4G/5G 蜂窝模块，支持中文短信查看、发送与删除（自动解码 UCS-2 / UTF-8）、语音通话记录管理与删除，以及原生 AT 命令交互。')),
			self.statusContainer,
			self.tabsContainer,
			self.bodyContainer
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
EOF_VIEW_JS

	cat > "$TARGET_DIR/po/zh_Hans/modemmanager.po" <<'EOF_PO_ZH'
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"
"Project-Id-Version: luci-app-modemmanager 1.0.0\n"
"Language: zh_Hans\n"
"MIME-Version: 1.0\n"
"Content-Transfer-Encoding: 8bit\n"

msgid "Modem"
msgstr "蜂窝模块"

msgid "ModemManager"
msgstr "ModemManager 管理"

msgid "ModemManager Management Center"
msgstr "ModemManager 调制解调器管理中心"

msgid "Manage 3G/4G/5G cellular modems via ModemManager (mmcli): view and delete SMS messages, manage voice call records, and control modem status."
msgstr "通过 ModemManager (mmcli) 管理 3G/4G/5G 蜂窝通信模块：支持中文短信查看、发送与删除，语音通话记录管理与删除，以及模块状态控制。"

msgid "Current Modem:"
msgstr "当前调制解调器："

msgid "Refresh Data"
msgstr "刷新数据"

msgid "Scan Modems"
msgstr "扫描模块"

msgid "Connection State"
msgstr "连接状态"

msgid "Signal Quality"
msgstr "信号质量"

msgid "Operator / Technology"
msgstr "运营商 / 网络制式"

msgid "Own Number"
msgstr "本机号码"

msgid "Manufacturer / Model"
msgstr "设备厂商 / 型号"

msgid "Firmware Revision"
msgstr "固件版本"

msgid "IMEI / Equipment ID"
msgstr "IMEI / 设备标识"

msgid "SIM ICCID / IMSI"
msgstr "SIM 卡 ICCID / IMSI"

msgid "SMS Storage (Default / Supported)"
msgstr "短信存储区（默认 / 支持）"

msgid "Primary Port / DBus Path"
msgstr "主通信端口 / 系统路径"

msgid "SMS Management"
msgstr "短信管理"

msgid "Call Records"
msgstr "通话记录"

msgid "Modem Control & USSD"
msgstr "模块控制与 USSD"

msgid "All SMS"
msgstr "全部短信"

msgid "Inbox (Received)"
msgstr "收件箱（已接收）"

msgid "Sent Messages"
msgstr "已发送"

msgid "Drafts / Stored"
msgstr "草稿 / 本地存储"

msgid "New SMS"
msgstr "发送新短信"

msgid "Delete Selected"
msgstr "删除选中"

msgid "Delete All SMS"
msgstr "清空全部短信"

msgid "Delete All Call Records"
msgstr "清空全部通话记录"

msgid "Dial Call"
msgstr "拨号呼叫"

msgid "Reply"
msgstr "回复"

msgid "Delete"
msgstr "删除"

msgid "Callback"
msgstr "回拨"

msgid "Accept"
msgstr "接听"

msgid "Hangup"
msgstr "挂断"
EOF_PO_ZH

	sed -i 's/\r$//' "$TARGET_DIR/build-apk.sh" "$TARGET_DIR/root/usr/libexec/rpcd/luci.modemmanager" "$TARGET_DIR/root/usr/bin/modemmanager-call-monitor" "$TARGET_DIR/root/usr/bin/modemmanager-enable-at" "$TARGET_DIR/root/etc/init.d/modemmanager-monitor" "$TARGET_DIR/root/usr/bin/modemmanager-sms-forwarder" 2>/dev/null || true
	chmod 0755 "$TARGET_DIR/build-apk.sh"
	chmod 0755 "$TARGET_DIR/root/usr/libexec/rpcd/luci.modemmanager"
	chmod 0755 "$TARGET_DIR/root/usr/bin/modemmanager-call-monitor"
	chmod 0755 "$TARGET_DIR/root/usr/bin/modemmanager-enable-at"
	chmod 0755 "$TARGET_DIR/root/etc/init.d/modemmanager-monitor"
	chmod 0755 "$TARGET_DIR/root/usr/bin/modemmanager-sms-forwarder"
	chmod 0644 "$TARGET_DIR/root/usr/share/luci/menu.d/luci-app-modemmanager.json"
	chmod 0644 "$TARGET_DIR/root/usr/share/rpcd/acl.d/luci-app-modemmanager.json"
	chmod 0644 "$TARGET_DIR/htdocs/luci-static/resources/view/modemmanager/index.js"
	chmod 0644 "$TARGET_DIR/po/zh_Hans/modemmanager.po"
}

do_install() {
	echo "[*] 正在安装 luci-app-modemmanager (中文增强版 v1.0.0-r21)..."
	TMP_DIR="$(mktemp -d)"
	trap 'rm -rf "$TMP_DIR"' EXIT
	extract_tree "$TMP_DIR"

	# 1. Force stop and kill any old background monitor processes in memory
	[ -x /etc/init.d/modemmanager-forwarder ] && (/etc/init.d/modemmanager-forwarder stop 2>/dev/null || true; /etc/init.d/modemmanager-forwarder disable 2>/dev/null || true)
	[ -x /etc/init.d/modemmanager-monitor ] && (/etc/init.d/modemmanager-monitor stop 2>/dev/null || true)
	rm -f /etc/init.d/modemmanager-forwarder /usr/bin/modemmanager-forwarder-loop /tmp/modemmanager-forwarder.pid /tmp/modemmanager-monitor.pid
	for pid in $( (ps -w 2>/dev/null || ps 2>/dev/null) | awk '/[m]odemmanager-call-monitor|[m]odemmanager-ca|[m]odemmanager-forwarder/ {print $1}' ); do
		kill -9 "$pid" 2>/dev/null || true
	done

	mkdir -p /usr/libexec/rpcd
	mkdir -p /usr/bin
	mkdir -p /etc/init.d
	mkdir -p /usr/share/luci/menu.d
	mkdir -p /usr/share/rpcd/acl.d
	mkdir -p /www/luci-static/resources/view/modemmanager

	cp "$TMP_DIR/root/usr/libexec/rpcd/luci.modemmanager" /usr/libexec/rpcd/luci.modemmanager
	cp "$TMP_DIR/root/usr/bin/modemmanager-call-monitor" /usr/bin/modemmanager-call-monitor
	cp "$TMP_DIR/root/usr/bin/modemmanager-enable-at" /usr/bin/modemmanager-enable-at
	cp "$TMP_DIR/root/etc/init.d/modemmanager-monitor" /etc/init.d/modemmanager-monitor
	cp "$TMP_DIR/root/usr/bin/modemmanager-sms-forwarder" /usr/bin/modemmanager-sms-forwarder
	sed -i 's/\r$//' /usr/libexec/rpcd/luci.modemmanager /usr/bin/modemmanager-call-monitor /usr/bin/modemmanager-enable-at /etc/init.d/modemmanager-monitor /usr/bin/modemmanager-sms-forwarder 2>/dev/null || true
	chmod 0755 /usr/libexec/rpcd/luci.modemmanager /usr/bin/modemmanager-call-monitor /usr/bin/modemmanager-enable-at /etc/init.d/modemmanager-monitor /usr/bin/modemmanager-sms-forwarder

	VIEW_NAME="index_$(date +%s 2>/dev/null || echo r21)"
	rm -f /www/luci-static/resources/view/modemmanager/index_*.js 2>/dev/null || true
	cp "$TMP_DIR/htdocs/luci-static/resources/view/modemmanager/index.js" /www/luci-static/resources/view/modemmanager/index.js
	cp "$TMP_DIR/htdocs/luci-static/resources/view/modemmanager/index.js" "/www/luci-static/resources/view/modemmanager/${VIEW_NAME}.js"
	chmod 0644 /www/luci-static/resources/view/modemmanager/index.js "/www/luci-static/resources/view/modemmanager/${VIEW_NAME}.js"

	sed "s|"modemmanager/index"|"modemmanager/${VIEW_NAME}"|g" "$TMP_DIR/root/usr/share/luci/menu.d/luci-app-modemmanager.json" > /usr/share/luci/menu.d/luci-app-modemmanager.json
	chmod 0644 /usr/share/luci/menu.d/luci-app-modemmanager.json

	cp "$TMP_DIR/root/usr/share/rpcd/acl.d/luci-app-modemmanager.json" /usr/share/rpcd/acl.d/luci-app-modemmanager.json
	chmod 0644 /usr/share/rpcd/acl.d/luci-app-modemmanager.json

	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ 2>/dev/null || true

	echo "[*] 正在将模块内短信与通话记录转存至本地数据库并释放模块存储空间..."
	/usr/bin/modemmanager-enable-at >/dev/null 2>&1 || true
	/usr/bin/ucode /usr/bin/modemmanager-sms-forwarder --init-seen >/dev/null 2>>/tmp/modemmanager_forward.log || true

	/etc/init.d/modemmanager-monitor enable 2>/dev/null || true
	/etc/init.d/modemmanager-monitor restart 2>/dev/null || true
	sleep 1

	if [ ! -f /tmp/modemmanager-monitor.pid ]; then
		start-stop-daemon -S -b -x /bin/sh -- /usr/bin/modemmanager-call-monitor --v21 >/dev/null 2>&1 || true
		sleep 1
	fi

	/etc/init.d/rpcd restart 2>/dev/null || true
	[ -x /etc/init.d/uhttpd ] && (/etc/init.d/uhttpd reload 2>/dev/null || true)

	if [ -f /tmp/modemmanager-monitor.pid ]; then
		echo "[+] 后台短信接收与自动转发守护进程已成功启动 (PID: $(cat /tmp/modemmanager-monitor.pid))"
	fi
	echo "[+] 更新完成！请在浏览器按 Ctrl+F5 强制刷新页面缓存，再点击一次『保存并应用配置』即可。"
}

do_uninstall() {
	echo "[*] 正在卸载 luci-app-modemmanager..."
	[ -x /etc/init.d/modemmanager-monitor ] && (/etc/init.d/modemmanager-monitor stop 2>/dev/null || true; /etc/init.d/modemmanager-monitor disable 2>/dev/null || true)
	[ -x /etc/init.d/modemmanager-forwarder ] && (/etc/init.d/modemmanager-forwarder stop 2>/dev/null || true; /etc/init.d/modemmanager-forwarder disable 2>/dev/null || true)
	for pid in $( (ps -w 2>/dev/null || ps 2>/dev/null) | awk '/[m]odemmanager-call-monitor|[m]odemmanager-ca|[m]odemmanager-forwarder/ {print $1}' ); do
		kill -9 "$pid" 2>/dev/null || true
	done
	rm -f /etc/init.d/modemmanager-monitor /etc/init.d/modemmanager-forwarder
	rm -f /usr/bin/modemmanager-call-monitor /usr/bin/modemmanager-enable-at /usr/bin/modemmanager-sms-forwarder /usr/bin/modemmanager-forwarder-loop
	rm -f /usr/libexec/rpcd/luci.modemmanager
	rm -f /usr/share/luci/menu.d/luci-app-modemmanager.json
	rm -f /usr/share/rpcd/acl.d/luci-app-modemmanager.json
	rm -f /usr/lib/lua/luci/i18n/modemmanager.zh-cn.lmo
	rm -rf /www/luci-static/resources/view/modemmanager
	rm -f /tmp/modemmanager-forwarder.pid /tmp/modemmanager-monitor.pid /tmp/modemmanager_forward.lock /tmp/modemmanager_forward.log
	rm -f /etc/modemmanager_call_meta.json /etc/modemmanager_at_presets.json /etc/modemmanager_sms_forward.json /etc/modemmanager_forward_state.json
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/ 2>/dev/null || true
	/etc/init.d/rpcd restart 2>/dev/null || true
	echo "[+] 卸载成功。"
}

ACTION="${1:---help}"
case "$ACTION" in
	--install|-i)
		do_install
		;;
	--uninstall|-u)
		do_uninstall
		;;
	--extract|-e)
		DEST="${2:-./luci-app-modemmanager}"
		extract_tree "$DEST"
		echo "[+] 已导出 OpenWrt LuCI 插件源码目录至: $DEST"
		;;
	--build-apk|-b)
		DEST="${2:-./luci-app-modemmanager}"
		extract_tree "$DEST"
		sh "$DEST/build-apk.sh" 1.0.0 21
		;;
	*)
		echo "用法: sh $0 [--install | --uninstall | --extract <dir> | --build-apk [dir]]"
		exit 0
		;;
esac