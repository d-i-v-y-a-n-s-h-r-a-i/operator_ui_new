# TANDAV Autonomous Marine GCS

Tactical 3D Marine Ground Control Station (GCS) and operator interface for autonomous maritime vessels. Features high-fidelity real-time 3D tactical situational awareness, 6-DoF attitude monitoring, sensor telemetry cards, autonomous mode controls, and collision-avoidance radar overlays.

---

## What to Download on a New Laptop (Quick Setup)

To run this project on any new Windows, macOS, or Linux laptop, follow these simple steps:

### 1. Download & Install Python
- Download **Python 3.10, 3.11, or 3.12** from [python.org](https://www.python.org/downloads/).
- **IMPORTANT**: During installation on Windows, make sure to check the box:
  `[x] Add python.exe to PATH`

### 2. Install Required Python Dependencies
Open your terminal (PowerShell, Command Prompt, or Bash) and run:
```bash
pip install PySide6
```
*(PySide6 includes the complete Qt 6 framework, Qt Quick, Qt Quick 3D, Qt 5 Compatibility module, and Qt Multimedia).*

### 3. Install Git & Git LFS (If cloning with video assets)
- Install Git from [git-scm.com](https://git-scm.com/).
- Initialize Git Large File Storage:
```bash
git lfs install
```

---

## How to Run the Application

### Option A: One-Click Launch (Windows)
Double-click either of the startup scripts in the project folder:
- **`run_ui.bat`** or **`TANDAV.bat`**

### Option B: Command Line Launch
Open a terminal in the project directory and run:
```bash
python launch_qml.py
```

### Option C: Launch with Mock Telemetry Simulation
To simulate live telemetry packets streaming over UDP from a vessel:
1. **Terminal 1** (Start the virtual vessel simulator):
   ```bash
   python mock_vessel.py
   ```
2. **Terminal 2** (Launch the GCS interface):
   ```bash
   python launch_qml.py
   ```

---

## Project Structure

```
operator_ui_new/
├── launch_qml.py          # Primary application bootstrap & telemetry bridge
├── tandav_gcs.pyw         # Standalone GUI launcher without console window
├── mock_vessel.py         # UDP telemetry generator for testing & simulation
├── run_ui.bat             # One-click Windows launcher
├── TANDAV.bat             # One-click Windows launcher
├── README.md              # Project documentation and setup guide
│
├── src/
│   ├── qml/
│   │   ├── main.qml               # Root UI window, header bar, bottom dock
│   │   ├── TacticalMapView.qml   # 3D marine scene, ocean surface, vessels & carousel
│   │   ├── TelemetryCard.qml     # Glassmorphic telemetry card component
│   │   ├── InstrumentCluster.qml # Auxiliary instrument cluster overlay
│   │   └── assets/
│   │       ├── meshes/            # 3D vessel models (neuboatYacht_mesh.mesh)
│   │       ├── fonts/             # Geometric stencil typography (SairaStencilOne.ttf)
│   │       ├── nav_path_gradient.png # Navigation path gradient shader
│   │       └── water_normal.png   # Ocean specular normal map
│   │
│   ├── backend/           # C++ telemetry and failsafe pipeline (optional native build)
│   └── models/            # C++ data models
│
├── config/                # Vessel dimensions, CG metrology, and hydrodynamics
├── jetson/                # Autonomous navigation daemons, CAN setup, and PID control
└── resources/             # Application icons and Qt Resource descriptors
```

---

## Troubleshooting

- **Qt Quick 3D / Graphics Driver Notice**: Ensure your graphics card drivers are up to date. Qt Quick 3D automatically selects Direct3D 11 / 12 on Windows, Metal on macOS, and Vulkan / OpenGL on Linux.
- **Font Rendering**: The application automatically registers `SairaStencilOne.ttf` located in `src/qml/assets/fonts/`. No manual font installation is required.
