#include "MissionPlan.h"
#include <QVariantMap>

MissionPlan::MissionPlan(QObject* parent) : QObject(parent) {}

int MissionPlan::count() const { return m_waypoints.size(); }
int MissionPlan::activeIndex() const { return m_activeIndex; }
double MissionPlan::totalDistance() const { return m_totalDistance; }

QVariantList MissionPlan::waypointsList() const {
    QVariantList list;
    for (int i = 0; i < m_waypoints.size(); ++i) {
        QVariantMap map;
        map["index"] = i + 1;
        map["latitude"] = m_waypoints[i].coordinate.latitude();
        map["longitude"] = m_waypoints[i].coordinate.longitude();
        map["speed"] = m_waypoints[i].speed;
        map["radius"] = m_waypoints[i].acceptanceRadius;
        list.append(map);
    }
    return list;
}

QVariantList MissionPlan::geofenceList() const {
    QVariantList list;
    for (const auto& coord : m_geofence) {
        QVariantMap map;
        map["latitude"] = coord.latitude();
        map["longitude"] = coord.longitude();
        list.append(map);
    }
    return list;
}

const QList<Waypoint>& MissionPlan::waypoints() const { return m_waypoints; }

void MissionPlan::addWaypoint(double lat, double lon, double speed, double radius) {
    m_waypoints.append({QGeoCoordinate(lat, lon), speed, radius});
    if (m_activeIndex < 0) {
        m_activeIndex = 0;
        emit activeIndexChanged(m_activeIndex);
    }
    recalculateDistance();
    emit countChanged(m_waypoints.size());
}

void MissionPlan::removeWaypoint(int index) {
    if (index >= 0 && index < m_waypoints.size()) {
        m_waypoints.removeAt(index);
        if (m_activeIndex >= m_waypoints.size()) {
            m_activeIndex = m_waypoints.size() - 1;
            emit activeIndexChanged(m_activeIndex);
        }
        recalculateDistance();
        emit countChanged(m_waypoints.size());
    }
}

void MissionPlan::clearWaypoints() {
    m_waypoints.clear();
    m_activeIndex = -1;
    m_totalDistance = 0.0;
    emit countChanged(0);
    emit activeIndexChanged(-1);
    emit totalDistanceChanged(0.0);
}

void MissionPlan::addGeofencePoint(double lat, double lon) {
    m_geofence.append(QGeoCoordinate(lat, lon));
    emit geofenceChanged();
}

void MissionPlan::clearGeofence() {
    m_geofence.clear();
    emit geofenceChanged();
}

void MissionPlan::setActiveIndex(int index) {
    if (index >= -1 && index < m_waypoints.size()) {
        if (m_activeIndex != index) {
            m_activeIndex = index;
            emit activeIndexChanged(m_activeIndex);
        }
    }
}

void MissionPlan::nextWaypoint() {
    if (m_activeIndex + 1 < m_waypoints.size()) {
        m_activeIndex++;
        emit activeIndexChanged(m_activeIndex);
    }
}

void MissionPlan::recalculateDistance() {
    double total = 0.0;
    for (int i = 0; i < m_waypoints.size() - 1; ++i) {
        total += m_waypoints[i].coordinate.distanceTo(m_waypoints[i + 1].coordinate);
    }
    if (!qFuzzyCompare(m_totalDistance, total)) {
        m_totalDistance = total;
        emit totalDistanceChanged(m_totalDistance);
    }
}

