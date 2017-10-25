#! /usr/bin/env python
# -*- coding=utf-8 -*-

import re
import pexpect
import logging.handlers
import cgi
from cStringIO import StringIO
import json
from wsgiref.simple_server import make_server
from multiprocessing.dummy import Pool as ThreadPool

CONST_SWITCH_H3C_TYPE = 1
CONST_SWITCH_CISCO_TYPE = 2
CONST_HTTP_PORT = 8001
CONST_SWITCH_CONFIG = {'port': 22, 'user': '', 'password': ''}

CONST_LOG_FILE = './switch.log'

logger = logging.getLogger('switch')
logger.setLevel(logging.DEBUG)
handler = logging.handlers.RotatingFileHandler(
    CONST_LOG_FILE,
    mode='a+',
    maxBytes=1073741824,  #1G
    backupCount=5)
handler.setFormatter(
    logging.Formatter(
        '%(asctime)s %(levelname)-8s[%(filename)s:%(lineno)d(%(funcName)s)] %(message)s'
    ))
logger.addHandler(handler)

pool = ThreadPool(32)


class SwitchExpection(Exception):
    """A switch operate error occurred."""


class SwitchLoginError(SwitchExpection):
    """A error occurred while login on to a switch."""


class SwitchUnImplementMethod(SwitchExpection):
    """A error occurred while call an funtion on switch object."""


class SwitchBase(object):
    def __init__(self, *args, **kwargs):
        self.host = kwargs['host']
        self.prompt = kwargs.get('prompt', '#>]')
        self.op_stat = True  #操作状态
        self.client = None
        self.timeout = 60
        pass

    def __del__(self):
        self.quit()

    def _login(self, host, port, user, password, expect, login_expect=None):
        client = pexpect.spawn(
            "ssh %s@%s -p %s" % (user, host, port), echo=False)
        ret = client.expect(
            [pexpect.TIMEOUT, pexpect.EOF, expect, '\(yes/no\)\?'],
            timeout=self.timeout)
        logger.info(client.before + str(client.after))

        if ret == 3:
            client.sendline('yes')
            ret = client.expect(
                [pexpect.TIMEOUT, pexpect.EOF, expect], timeout=self.timeout)
        if ret == 2:
            client.sendline(str(password))
            login_expect = login_expect if login_expect else self.prompt
            ret = client.expect(
                [pexpect.TIMEOUT, pexpect.EOF, login_expect],
                timeout=self.timeout)
            logger.info(client.before + str(client.after))
            if ret == 2:
                self.client = client
                return True
        raise SwitchLoginError("login on to the switch:%s failed" % (host))

    def enter_port(self, portname):
        return self.exec_cmd("interface %s" % (portname))

    def exec_cmd(self, cmd, expect=None, result=True):
        if not self.client:
            msg = "exec cmd , but not login. Please login in switch first..."
            logger.error(msg)
            raise SwitchExpection(msg)

        if not expect:
            expect = self.prompt

        self.client.sendline(cmd)
        ret = self.client.expect(
            [pexpect.TIMEOUT, pexpect.EOF, expect], timeout=self.timeout)
        content = self.client.before + str(self.client.after)
        logger.info('执行命令 %s , 返回结果 %s' % (cmd, content))
        if ret == 2:
            if result:
                return content
            else:
                return True
        else:
            msg = '执行命令出错:\'%s\' \n 期望返回结果包含:\'%s\'\n 实际输出:\'%s\' ' % (
                cmd, expect, content)
            logger.error(msg)
            raise SwitchExpection(msg)

    def save(self):
        raise SwitchUnImplementMethod("Not Implement!!!!")

    def quit(self):
        if self.client:
            self.client.terminate()
            self.client = None
        logger.info("quit switch")


class SwitchCisco(SwitchBase):
    def __init__(self, *args, **kwargs):
        SwitchBase.__init__(self, *args, **kwargs)
        self._login(self.host, kwargs['port'], kwargs['user'],
                    kwargs['password'], "assword:")
        self.exec_cmd("configure terminal")

    def get_vlan_list(self):
        self.exec_cmd("display interface brief", "More")

    def show_vlan_prop(self, portname):
        self.exec_cmd("show running-config interface %s" % portname)
        prop = self.client.before + str(self.client.after)
        prop = re.search('\r\ninterface(.*)', prop, re.DOTALL)
        logger.info(str(prop))
        if prop:
            return prop.groups()[0].strip()
        else:
            return ""

    def show_mac_address(self, portname):
        self.exec_cmd("show mac address-table interface %s" % portname)
        mac = self.client.before + str(self.client.after)
        mac = re.search('\+------------------\r\n(.*)\r\n\r', mac, re.DOTALL)
        logger.info(str(mac))
        if mac:
            mac = mac.groups()[0].strip()
            if mac:
                mac = mac.split()[2]
                mac = ''.join([i.upper() for i in mac.split('.')])
                return mac
        return ""

    def set_port_access(self, portname, vlanid):
        raise SwitchUnImplementMethod("Not Implement!!!!")

    def set_port_trunk(self, portname):
        raise SwitchUnImplementMethod("Not Implement!!!!")

    def shutdown(self, portname):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd("shutdown")
        self.op_stat = self.op_stat and self.save()
        return self.op_stat

    def unshutdown(self, portname):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd("no shutdown")
        self.op_stat = self.op_stat and self.save()
        return self.op_stat


class SwitchH3C(SwitchBase):
    def __init__(self, *args, **kwargs):
        SwitchBase.__init__(self, prompt=']', *args, **kwargs)
        self._login(self.host, kwargs['port'], kwargs['user'],
                    kwargs['password'], "assword:", ">")
        self.exec_cmd("system-view")

    def get_vlan_list(self):
        self.exec_cmd("display interface brief", "More")

    def show_vlan_prop(self, portname):
        self.exec_cmd("display current-configuration interface %s" % portname)
        prop = self.client.before + str(self.client.after)
        prop = re.search('#(.*)#', prop, re.DOTALL)
        logger.info(str(prop))
        if prop:
            return prop.groups()[0].strip()
        else:
            return ""

    def show_mac_address(self, portname):
        self.exec_cmd("display mac-address interface %s" % portname)
        mac = self.client.before + str(self.client.after)
        mac = re.search('Port/NickName            Aging(.*)\[', mac, re.DOTALL)
        logger.info(str(mac))
        if mac:
            mac = mac.groups()[0].strip()
            if mac:
                mac = mac.split()[0]
                mac = ''.join([i.upper() for i in mac.split('-')])
                return mac
        return ""

    def save(self):
        """
        save  y  回车   y
        :return:
        """
        self.op_stat = self.op_stat and self.exec_cmd("save", "\[Y/N\]:")
        self.op_stat = self.op_stat and self.exec_cmd("y",
                                                      "press the enter key\):")
        self.op_stat = self.op_stat and self.exec_cmd("\n", "\[Y/N\]:")
        self.op_stat = self.op_stat and self.exec_cmd("y", "successfully.")
        return self.op_stat

    def set_port_access(self, portname, vlanid):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd('port access vlan %s' %
                                                      (vlanid))
        self.op_stat = self.op_stat and self.exec_cmd('stp edged-port')
        self.op_stat = self.op_stat and self.exec_cmd('undo shutdown')
        self.op_stat = self.op_stat and self.exec_cmd('description TO Server')
        self.op_stat = self.op_stat and self.save()
        return self.op_stat

    def set_port_trunk(self, portname):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd('port link-type trunk')
        self.op_stat = self.op_stat and self.exec_cmd('stp edged-port')
        self.op_stat = self.op_stat and self.exec_cmd(
            'port trunk permit vlan 2 to 2999 3001 to 4094')
        self.op_stat = self.op_stat and self.exec_cmd(
            'undo port trunk permit vlan 1')
        self.op_stat = self.op_stat and self.exec_cmd('undo shutdown')
        self.op_stat = self.op_stat and self.exec_cmd('description TO Server')
        self.op_stat = self.op_stat and self.save()
        return self.op_stat

    def shutdown(self, portname):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd("shutdown")
        self.op_stat = self.op_stat and self.save()
        return self.op_stat

    def unshutdown(self, portname):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd("undo shutdown")
        self.op_stat = self.op_stat and self.save()
        return self.op_stat


class SwitchCiscoNexus(SwitchCisco):
    def __init__(self, *args, **kwargs):
        SwitchCisco.__init__(self, prompt='#', *args, **kwargs)

    def save(self):
        self.op_stat = self.op_stat and self.exec_cmd(
            "copy running-config startup-config",
            "Copy complete, now saving to disk")
        return self.op_stat

    def set_port_access(self, portname, vlanid):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd(
            'switchport access vlan %s' % (vlanid))
        self.op_stat = self.op_stat and self.exec_cmd('no shutdown')
        self.op_stat = self.op_stat and self.exec_cmd('description TO Server')
        self.op_stat = self.op_stat and self.save()
        return self.op_stat

    def set_port_trunk(self, portname):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd(
            'no switchport access vlan 999')
        self.op_stat = self.op_stat and self.exec_cmd('switchport mode trunk')
        self.op_stat = self.op_stat and self.exec_cmd(
            'switchport trunk allowed vlan 100-103,111-118,121-124,131-132,135-166,999'
        )
        self.op_stat = self.op_stat and self.exec_cmd('no shutdown')
        self.op_stat = self.op_stat and self.exec_cmd('description TO Server')
        self.op_stat = self.op_stat and self.save()
        return self.op_stat


class SwitchCiscoCatalyst(SwitchCisco):
    def __init__(self, *args, **kwargs):
        SwitchCisco.__init__(self, prompt='#', *args, **kwargs)

    def show_vlan_prop(self, portname):
        self.exec_cmd("do show running-config interface %s" % portname)
        prop = self.client.before + str(self.client.after)
        prop = re.search('\r\ninterface(.*)end', prop, re.DOTALL)
        logger.info(str(prop))
        if prop:
            return prop.groups()[0].strip()
        else:
            return ""

    def show_mac_address(self, portname):
        self.exec_cmd("do show mac address-table interface %s" % portname)
        mac = self.client.before + str(self.client.after)
        mac = re.search('    -----\r\n(.*)\r\nTotal', mac, re.DOTALL)
        logger.info(str(mac))
        if mac:
            mac = mac.groups()[0].strip()
            if mac:
                mac = mac.split()[1]
                mac = ''.join([i.upper() for i in mac.split('.')])
                return mac
        return ""

    def save(self):
        self.op_stat = self.op_stat and self.exec_cmd("do write", "\[OK\]")
        return self.op_stat

    def set_port_access(self, portname, vlanid):
        self.op_stat = self.op_stat and self.enter_port(portname)
        self.op_stat = self.op_stat and self.exec_cmd(
            'switchport access vlan %s' % (vlanid))
        self.op_stat = self.op_stat and self.exec_cmd('switchport mode access')
        self.op_stat = self.op_stat and self.exec_cmd('no shutdown')
        self.op_stat = self.op_stat and self.exec_cmd('description TO Server')
        self.op_stat = self.op_stat and self.save()
        return self.op_stat

    def set_port_trunk(self, portname):
        raise SwitchUnImplementMethod("Not Implement!!!!")


class SwitchMgr(object):
    SWITCH_TYPE_TO_CLASS = {
        'C3048': SwitchCiscoNexus,
        'C3064': SwitchCiscoNexus,
        'C2960': SwitchCiscoCatalyst,
        'H1650': SwitchH3C,
        'H3100': SwitchH3C,
        'H3110': SwitchH3C,
        'H5130': SwitchH3C,
        'H5560': SwitchH3C,
        'H6300': SwitchH3C,
        'H6800': SwitchH3C
    }

    def __init__(self, host, switch_type):
        logger.info("create switch manager by host:%s and switch_type:%s" %
                    (host, switch_type))
        self.host = host
        try:
            self.cls = self.SWITCH_TYPE_TO_CLASS[switch_type]
        except Exception as err:
            msg = '没有找到对应型号的交换机 请配置 SWITCH_TYPE_TO_CLASS 后 再使用 %s' % str(err)
            logger.error(msg)
            raise SwitchExpection(msg)

    def switch_obj(self):
        switch_config = CONST_SWITCH_CONFIG.copy()
        switch_config.update({'host': self.host})
        return self.cls(switch_config)

    def get_port_prop(self, portname):
        return self.switch_obj().show_vlan_prop(portname)

    def show_mac_address(self, portname):
        return self.switch_obj().show_mac_address(portname)

    def exec_cmd(self, portname, cmd_list):
        switch_obj = self.switch_obj()
        ret = switch_obj.enter_port(portname)
        for cmd in cmd_list:
            if not (ret and switch_obj.exec_cmd(cmd)):
                return False
        return switch_obj.save()

    def set_port_config(self, portname, port_type, vlanid=999):
        if port_type == 'access':
            return self.switch_obj().set_port_access(portname, vlanid)
        elif port_type == 'trunk':
            return self.switch_obj().set_port_trunk(portname)
        else:
            logger.error("unkown port type:%s" % (port_type))
            return False

    def shutdown(self, portname):
        return self.switch_obj().shutdown(portname)

    def unshutdown(self, portname):
        return self.switch_obj().unshutdown(portname)


def do_task(ip, switch_type, command):
    switch_config = CONST_SWITCH_CONFIG.copy()
    switch_config.update({'host': ip})
    if switch_type == 'h3c':
        netdev = SwitchH3C(switch_config)
    elif switch_type == 'nexus':
        netdev = SwitchCiscoNexus(switch_config)
    elif switch_type == 'catalyst':
        netdev = SwitchCiscoCatalyst(switch_config)

    try:
        result = netdev.exec_cmd(command, netdev.prompt)
    except SwitchExpection as err:
        logger.error(err)
        result = err
    finally:
        netdev.quit()
    return result


#todo 权限控制
def check_access(post_data):
    return True


#主函数
def application(environ, start_response):
    status = '200 OK'

    headers = [('Content-Type', 'application/json')]

    start_response(status, headers)
    a = {}
    if environ['REQUEST_METHOD'] in ['POST', 'PUT']:
        if environ.get('CONTENT_TYPE', '').lower().startswith('multipart/'):
            fp = environ['wsgi.input']
            a = cgi.FieldStorage(fp=fp, environ=environ, keep_blank_values=1)
        else:
            fp = StringIO(environ.get('wsgi.input').read())
            a = cgi.FieldStorage(fp=fp, environ=environ, keep_blank_values=1)
    else:
        a = cgi.FieldStorage(environ=environ, keep_blank_values=1)

    post_data = {}
    for key in a.keys():
        post_data[key] = a[key].value
    logger.info('POST的内容是 : ip %s , post_data %s ' %
                (environ.get('REMOTE_ADRR'), json.dumps(post_data)))

    if not check_access(post_data):
        return json.dumps({'code': 403, 'message': '没权限', 'data': ''})
    else:
        switch_ip = post_data.get('ip')
        switch_type = post_data.get('switch_type')
        command = post_data.get('command')
        if not switch_ip or not switch_type or not command:
            return json.dumps({'code': 500, 'message': '参数不对', 'data': ''})
        result = pool.apply(do_task, kwds=post_data)
        pool.join()
        return json.dumps({'code': 200, 'message': '执行成功', 'data': result})


if __name__ == '__main__':
    http_server = make_server('', CONST_HTTP_PORT, application)
    http_server.serve_forever()
