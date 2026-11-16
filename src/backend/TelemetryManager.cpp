#include "TelemetryManager.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>

TelemetryManager::TelemetryManager(VesselState* state, MissionPlan* mission, QObject* parent)
    : QObject(parent), m_vesselState(state), m_missionPlan(mission) {
    m_socket = new QUdpSocket(this);
    m_heartbeatTimer = new QTimer(this);

    connect(m_socket, &QUdpSocket::readyRead, this, &TelemetryManager::readPendingDatagrams);
    connect(m_heartbeatTimer, &QTimer::timeout, this, &TelemetryManager::sendHeartbeat);
}

bool TelemetryManager::isConnected() const { return m_connected; }
QString TelemetryManager::hostAddress() const { return m_targetHost.toString(); }
quint16 TelemetryManager::port() const { return m_listenPort; }
quint16 TelemetryManager::sendPort() const { return m_targetPort; }

void TelemetryManager::setHostAddress(const QString& address) {
    QHostAddress addr(address);
    if (addr != m_targetHost) {
        m_targetHost = addr;
        emit networkConfigChanged();
    }
}

void TelemetryManager::setPort(quint16 port) {
    if (m_listenPort != port) {
        m_listenPort = port;
        emit networkConfigChanged();
    }
}

void TelemetryManager::setSendPort(quint16 port) {
    if (m_targetPort != port) {
        m_targetPort = port;
        emit networkConfigChanged();
    }
}

bool TelemetryManager::startListening() {
    if (m_socket->state() == QAbstractSocket::BoundState) {
        m_socket->close();
    }
    bool bound = m_socket->bind(QHostAddress::AnyIPv4, m_listenPort, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint);
    if (bound) {
        m_heartbeatTimer->start(500);
        m_lastPacketTimer.start();
        m_connected = true;
        emit connectionChanged(true);
    } else {
        emit errorOccurred(m_socket->errorString());
    }
    return bound;
}

void TelemetryManager::stopListening() {
    m_heartbeatTimer->stop();
    m_socket->close();
    m_connected = false;
    emit connectionChanged(false);
}

void TelemetryManager::readPendingDatagrams() {
    while (m_socket->hasPendingDatagrams()) {
        QByteArray datagram;
        datagram.resize(int(m_socket->pendingDatagramSize()));
        QHostAddress sender;
        quint16 senderPort;
        m_socket->readDatagram(datagram.data(), datagram.size(), &sender, &senderPort);

        qint64 elapsed = m_lastPacketTimer.restart();
        if (m_vesselState) {
            m_vesselState->setLatencyMs(int(elapsed));
        }

        if (datagram.startsWith('{')) {
            parseTelemetryJson(datagram);
        } else if (datagram.size() == sizeof(CanFramePacket)) {
            parseCanBusFrame(datagram);
        } else {
            parseTelemetryBinary(datagram);
        }
        emit packetReceived();
    }
}

void TelemetryManager::parseCanBusFrame(const QByteArray& data) {
    if (data.size() < int(sizeof(CanFramePacket)) || !m_vesselState) return;
    const auto* p = reinterpret_cast<const CanFramePacket*>(data.constData());

    if (p->canId == 0x200) {
        uint16_t rpm = (static_cast<uint8_t>(p->payload[0]) << 8) | static_cast<uint8_t>(p->payload[1]);
        double coolant = static_cast<uint8_t>(p->payload[2]) - 40.0;
        m_vesselState->setRpm(rpm);
        m_vesselState->setCoolantTemp(coolant);
    } else if (p->canId == 0x208) {
        double throttle = static_cast<uint8_t>(p->payload[3]) * 0.4;
        Q_UNUSED(throttle);
    } else if (p->canId == 0x300) {
        uint16_t rawV = (static_cast<uint8_t>(p->payload[4]) << 8) | static_cast<uint8_t>(p->payload[5]);
        double voltage = rawV * 0.01;
        m_vesselState->setBatteryVoltage(voltage);
    } else if (p->canId == 0x18FF) {
        bool leak = (p->payload[0] & 0x01) != 0;
        m_vesselState->setLeakDetected(leak);
    }
}

void TelemetryManager::parseTelemetryJson(const QByteArray& data) {
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject() || !m_vesselState) return;

    QJsonObject obj = doc.object();
    if (obj.contains("pitch")) m_vesselState->setPitch(obj["pitch"].toDouble());
    if (obj.contains("roll")) m_vesselState->setRoll(obj["roll"].toDouble());
    if (obj.contains("yaw")) m_vesselState->setYaw(obj["yaw"].toDouble());
    if (obj.contains("lat") && obj.contains("lon")) {
        m_vesselState->setPosition(obj["lat"].toDouble(), obj["lon"].toDouble());
    }
    if (obj.contains("speed")) m_vesselState->setSpeed(obj["speed"].toDouble());
    if (obj.contains("heading")) m_vesselState->setHeading(obj["heading"].toDouble());
    if (obj.contains("bat_v")) m_vesselState->setBatteryVoltage(obj["bat_v"].toDouble());
    if (obj.contains("bat_a")) m_vesselState->setBatteryCurrent(obj["bat_a"].toDouble());
    if (obj.contains("bat_pct")) m_vesselState->setBatteryPercentage(obj["bat_pct"].toInt());
    if (obj.contains("bat_temp")) m_vesselState->setBatteryTemp(obj["bat_temp"].toDouble());
    if (obj.contains("th_l") && obj.contains("th_r")) {
        m_vesselState->setThrusters(obj["th_l"].toDouble(), obj["th_r"].toDouble());
    }
    if (obj.contains("depth")) m_vesselState->setDepth(obj["depth"].toDouble());
    if (obj.contains("w_temp")) m_vesselState->setWaterTemp(obj["w_temp"].toDouble());
    if (obj.contains("leak")) m_vesselState->setLeakDetected(obj["leak"].toBool());
    if (obj.contains("armed")) m_vesselState->setArmed(obj["armed"].toBool());
    if (obj.contains("mode")) m_vesselState->setMode(obj["mode"].toString());
    if (obj.contains("link_q")) m_vesselState->setLinkQuality(obj["link_q"].toInt());
    if (obj.contains("rpm")) m_vesselState->setRpm(obj["rpm"].toInt());
    if (obj.contains("coolant")) m_vesselState->setCoolantTemp(obj["coolant"].toDouble());
    if (obj.contains("target_hdg")) m_vesselState->setTargetHeading(obj["target_hdg"].toDouble());
    if (obj.contains("target_spd")) m_vesselState->setTargetSpeed(obj["target_spd"].toDouble());

    if (obj.contains("type") && obj["type"].toString() == "THREATS" && obj.contains("threats")) {
        QJsonArray arr = obj["threats"].toArray();
        QVariantList list;
        for (const auto& val : arr) {
            list.append(val.toObject().toVariantMap());
        }
        m_vesselState->setThreats(list);
    }
}

#pragma pack(push, 1)
struct BinaryTelemetryPacket {
    uint32_t magic;
    uint32_t seq;
    float pitch;
    float roll;
    float yaw;
    double lat;
    double lon;
    float speed;
    float heading;
    float batVoltage;
    float batCurrent;
    uint8_t batPct;
    float batTemp;
    float thLeft;
    float thRight;
    float depth;
    float waterTemp;
    uint8_t leak;
    uint8_t armed;
    uint8_t mode;
    uint8_t linkQuality;
};
#pragma pack(pop)

void TelemetryManager::parseTelemetryBinary(const QByteArray& data) {
    if (data.size() < int(sizeof(BinaryTelemetryPacket)) || !m_vesselState) return;
    const auto* p = reinterpret_cast<const BinaryTelemetryPacket*>(data.constData());
    if (p->magic != 0x544E4456) return;

    m_vesselState->setPitch(p->pitch);
    m_vesselState->setRoll(p->roll);
    m_vesselState->setYaw(p->yaw);
    m_vesselState->setPosition(p->lat, p->lon);
    m_vesselState->setSpeed(p->speed);
    m_vesselState->setHeading(p->heading);
    m_vesselState->setBatteryVoltage(p->batVoltage);
    m_vesselState->setBatteryCurrent(p->batCurrent);
    m_vesselState->setBatteryPercentage(p->batPct);
    m_vesselState->setBatteryTemp(p->batTemp);
    m_vesselState->setThrusters(p->thLeft, p->thRight);
    m_vesselState->setDepth(p->depth);
    m_vesselState->setWaterTemp(p->waterTemp);
    m_vesselState->setLeakDetected(p->leak != 0);
    m_vesselState->setArmed(p->armed != 0);
    m_vesselState->setLinkQuality(p->linkQuality);
}

void TelemetryManager::sendControlPacket(double leftThruster, double rightThruster, bool armed, const QString& mode) {
    QJsonObject obj;
    obj["type"] = "CONTROL";
    obj["seq"] = double(++m_packetSequence);
    obj["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    obj["th_l"] = leftThruster;
    obj["th_r"] = rightThruster;
    obj["armed"] = armed;
    obj["mode"] = mode;

    QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->writeDatagram(data, m_targetHost, m_targetPort);
    emit packetSent();
}

void TelemetryManager::sendHeartbeat() {
    QJsonObject obj;
    obj["type"] = "HEARTBEAT";
    obj["seq"] = double(++m_packetSequence);
    obj["timestamp"] = QDateTime::currentMSecsSinceEpoch();

    QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->writeDatagram(data, m_targetHost, m_targetPort);
    emit packetSent();
}

void TelemetryManager::sendArmDisarm(bool arm) {
    if (m_vesselState) {
        sendControlPacket(m_vesselState->leftThruster(), m_vesselState->rightThruster(), arm, m_vesselState->mode());
        m_vesselState->setArmed(arm);
    }
}

void TelemetryManager::sendMode(const QString& mode) {
    if (m_vesselState) {
        sendControlPacket(m_vesselState->leftThruster(), m_vesselState->rightThruster(), m_vesselState->armed(), mode);
        m_vesselState->setMode(mode);
    }
}

void TelemetryManager::sendEmergencyStop() {
    if (m_vesselState) {
        m_vesselState->setThrusters(0.0, 0.0);
        m_vesselState->setArmed(false);
        m_vesselState->setMode("ESTOP");
    }
    sendControlPacket(0.0, 0.0, false, "ESTOP");
}

void TelemetryManager::uploadMission() {
    if (!m_missionPlan) return;
    QJsonObject obj;
    obj["type"] = "MISSION_UPLOAD";
    obj["seq"] = double(++m_packetSequence);
    obj["timestamp"] = QDateTime::currentMSecsSinceEpoch();

    QJsonArray wpArray;
    const auto& waypoints = m_missionPlan->waypoints();
    for (int i = 0; i < waypoints.size(); ++i) {
        QJsonObject wp;
        wp["index"] = i + 1;
        wp["lat"] = waypoints[i].coordinate.latitude();
        wp["lon"] = waypoints[i].coordinate.longitude();
        wp["speed"] = waypoints[i].speed;
        wp["radius"] = waypoints[i].acceptanceRadius;
        wpArray.append(wp);
    }
    obj["waypoints"] = wpArray;

    QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->writeDatagram(data, m_targetHost, m_targetPort);
    emit packetSent();
    emit m_missionPlan->missionUploaded();
}

void TelemetryManager::sendPidGains(double kpHdg, double kiHdg, double kdHdg, double kpSpd, double kiSpd, double kdSpd) {
    QJsonObject obj;
    obj["type"] = "PID_CONFIG";
    obj["seq"] = double(++m_packetSequence);
    obj["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    obj["kp_hdg"] = kpHdg;
    obj["ki_hdg"] = kiHdg;
    obj["kd_hdg"] = kdHdg;
    obj["kp_spd"] = kpSpd;
    obj["ki_spd"] = kiSpd;
    obj["kd_spd"] = kdSpd;

    QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->writeDatagram(data, m_targetHost, m_targetPort);
    emit packetSent();

    if (m_vesselState) {
        m_vesselState->setPidGains(kpHdg, kiHdg, kdHdg, kpSpd, kiSpd, kdSpd);
    }
}

void TelemetryManager::sendTargetSpeed(double speed) {
    QJsonObject obj;
    obj["type"] = "SET_TARGET_SPEED";
    obj["seq"] = double(++m_packetSequence);
    obj["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    obj["speed"] = speed;

    QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->writeDatagram(data, m_targetHost, m_targetPort);
    emit packetSent();

    if (m_vesselState) {
        m_vesselState->setTargetSpeed(speed);
    }
}

void TelemetryManager::sendTargetHeading(double heading) {
    QJsonObject obj;
    obj["type"] = "SET_TARGET_HEADING";
    obj["seq"] = double(++m_packetSequence);
    obj["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    obj["heading"] = heading;

    QByteArray data = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->writeDatagram(data, m_targetHost, m_targetPort);
    emit packetSent();

    if (m_vesselState) {
        m_vesselState->setTargetHeading(heading);
    }
}
