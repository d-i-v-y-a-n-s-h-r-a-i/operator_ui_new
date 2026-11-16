#pragma once

#include <QObject>
#include <QGeoCoordinate>
#include <QVariantList>
#include <QList>

struct Waypoint {
    QGeoCoordinate coordinate;
    double speed;
    double acceptanceRadius;
};

class MissionPlan : public QObject {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int activeIndex READ activeIndex WRITE setActiveIndex NOTIFY activeIndexChanged)
    Q_PROPERTY(double totalDistance READ totalDistance NOTIFY totalDistanceChanged)
    Q_PROPERTY(QVariantList waypointsList READ waypointsList NOTIFY countChanged)
    Q_PROPERTY(QVariantList geofenceList READ geofenceList NOTIFY geofenceChanged)

public:
    explicit MissionPlan(QObject* parent = nullptr);

    int count() const;
    int activeIndex() const;
    double totalDistance() const;
    QVariantList waypointsList() const;
    QVariantList geofenceList() const;
    const QList<Waypoint>& waypoints() const;

    Q_INVOKABLE void addWaypoint(double lat, double lon, double speed = 2.0, double radius = 5.0);
    Q_INVOKABLE void removeWaypoint(int index);
    Q_INVOKABLE void clearWaypoints();
    Q_INVOKABLE void addGeofencePoint(double lat, double lon);
    Q_INVOKABLE void clearGeofence();
    Q_INVOKABLE void setActiveIndex(int index);
    Q_INVOKABLE void nextWaypoint();

signals:
    void countChanged(int count);
    void activeIndexChanged(int index);
    void totalDistanceChanged(double distance);
    void geofenceChanged();
    void missionUploaded();

private:
    void recalculateDistance();

    QList<Waypoint> m_waypoints;
    QList<QGeoCoordinate> m_geofence;
    int m_activeIndex{-1};
    double m_totalDistance{0.0};
};

