#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import signal
import paho.mqtt.client as mqtt
import subprocess
import time
import re
import configparser as ConfigParser
import threading
import os

# Default configuration
config = {
    'mqtt': {
        'broker': 'localhost',
        'port': 1883,
        'prefix': 'media',
        'user': os.environ.get('MQTT_USER'),
        'password': os.environ.get('MQTT_PASSWORD'),
    },
    'cec': {
        'enabled': 0,
        'id': 1,
        'port': 'RPI',
        'devices': '0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15',
    }
}


def mqtt_send(topic, value, retain=False):
    mqtt_client.publish(topic, value, retain=retain)


def cec_on_keypress(key, duration):
    print("[key pressed] " + str(key) + ", "+ str(duration))
    return 0


def cec_command_callback(cmd):
    print("CEC RX: " + str(cmd))

    if cmd == ">> 05:c3":
        print("CCC: request ARC start (C3)")
        print("CCC: Reporting ARC started (C1)")
        cec_send("50:C1")
        return 1

    return 0

def cec_alert_callback(alert, param):
    print("CEC ALERT: " + str(alert) + ", " + str(param))

def cec_on_message(level, time, message):
    if level == cec.CEC_LOG_ERROR:
        print("CEC_LOG_ERROR: %s" % message)

    if level == cec.CEC_LOG_WARNING:
        print("CEC_LOG_WARNING: %s" % message)

    if level == cec.CEC_LOG_NOTICE:
        print("CEC_LOG_NOTICE: %s" % message)

    if level == cec.CEC_LOG_DEBUG:
        print("CEC_LOG_DEBUG: %s" % message)

    if level == cec.CEC_LOG_TRAFFIC:

        # m = re.search('>> ([0-9a-f:]+)', message)
        # if m:
        #   print("CEC RX: %s" % m.group(1))

        m = re.search('<< ([0-9a-f:]+)', message)
        if m:
            print("CEC TX: %s" % m.group(1))

        # m = re.search('>> 05:c3', message)
        # if m:
        #     print("request ARC start (C3)")
        #     print("Reporting ARC started (C1)")
        #     cec_send("50:C1")

        # TODO: Move to command callback
        m = re.search('>> [0-9a-f]{2}:44:([0-9a-f]{2})', message)
        if m:
            handleKeyPress(m.group(1))
            return 0

        m = re.search('>> [0-9a-f]{2}:8b:([0-9a-f]{2})', message)
        if m:
            handleKeyRelease(m.group(1))
            return 0

    return 0


def cec_send(cmd, id=None):
    if id is None:
        cec_client.Transmit(cec_client.CommandFromString(cmd))
    else:
        cec_client.Transmit(cec_client.CommandFromString(
            '1%s:%s' % (hex(id)[2:], cmd)))


def translateKey(key):
    localKey = None

    if key == "41":
        localKey = "volumeup"
    elif key == "42":
        localKey = "volumedown"
    elif key == "43":
        localKey = "volumemute"

    return localKey


def handleKeyPress(key):
    remoteKey = translateKey(key)

    if remoteKey == None:
        return

    print("Sending key press " + remoteKey + " to MQTT")
    mqtt_send(config['mqtt']['prefix'] + '/cec/' + remoteKey, 'on', True)


def handleKeyRelease(key):
    remoteKey = translateKey(key)

    if remoteKey == None:
        return

    print("Sending key release " + remoteKey + " to MQTT")
    mqtt_send(config['mqtt']['prefix'] + '/cec/' + remoteKey, 'off', True)


def cec_refresh():
    try:
        for id in config['cec']['devices'].split(','):
            cec_send('8F', id=int(id))

    except Exception as e:
        print("Error during refreshing: ", str(e))


def cleanup():
    mqtt_client.loop_stop()
    mqtt_client.disconnect()


class GracefulKiller:
    kill_now = False

    def __init__(self):
        signal.signal(signal.SIGINT, self.exit_gracefully)
        signal.signal(signal.SIGTERM, self.exit_gracefully)

    def exit_gracefully(self, signum, frame):
        self.kill_now = True


try:
    ### Parse config ###
    killer = GracefulKiller()
    try:
        Config = ConfigParser.SafeConfigParser()
        if Config.read("/home/pi/scripts/config.ini"):

            # Load all sections and overwrite default configuration
            for section in Config.sections():
                config[section].update(dict(Config.items(section)))

        # Environment variables
        for section in config:
            for key, value in config[section].items():
                env = os.getenv(section.upper() + '_' + key.upper())
                if env:
                    config[section][key] = type(value)(env)

        # Do some checks
        if not int(config['cec']['enabled']) == 1:
            raise Exception('CEC is disabled. Can\'t continue.')

    except Exception as e:
        print("ERROR: Could not configure:", str(e))
        exit(1)

    ### Setup CEC ###
    if int(config['cec']['enabled']) == 1:
        print("Initialising CEC...")
        try:
            import cec
            global repeatingKey

            repeatingKey = None

            cec_config = cec.libcec_configuration()
            cec_config.strDeviceName = "DomoAudio"
            cec_config.bActivateSource = 0
            cec_config.deviceTypes.Add(cec.CEC_DEVICE_TYPE_AUDIO_SYSTEM)
            cec_config.clientVersion = cec.LIBCEC_VERSION_CURRENT
            cec_config.SetLogCallback(cec_on_message)
            cec_config.SetKeyPressCallback(cec_on_keypress)
            cec_config.SetCommandCallback(cec_command_callback)
            cec_config.SetAlertCallback(cec_alert_callback)
            cec_client = cec.ICECAdapter.Create(cec_config)
            if not cec_client.Open(config['cec']['port']):
                raise Exception("Could not connect to cec adapter")
            # Set system audio status = On
            cec_send("50:72:01:00")
            # System audio mode status = On
            cec_send("50:7E:01:00")
        except Exception as e:
            print("ERROR: Could not initialise CEC:", str(e))
            exit(1)

    ### Setup MQTT ###
    print("Initialising MQTT...")
    mqtt_client = mqtt.Client("cec-ir-mqtt")
    if config['mqtt']['user']:
        mqtt_client.username_pw_set(
            config['mqtt']['user'], password=config['mqtt']['password'])
    mqtt_client.connect(config['mqtt']['broker'],
                        int(config['mqtt']['port']), 60)
    mqtt_client.loop_start()

    print("Starting main loop...")
    while True:
        time.sleep(10)

        if killer.kill_now:
            break

except KeyboardInterrupt:
    cleanup()

except RuntimeError:
    cleanup()
