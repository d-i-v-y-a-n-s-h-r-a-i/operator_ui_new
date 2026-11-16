import json
import math
import os
import sys

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "hull_cg_metrology.json")

def load_metrology():
    with open(CONFIG_PATH, "r") as f:
        return json.load(f)

def compute_center_of_gravity(manifest):
    total_mass = sum(c["mass_kg"] for c in manifest)
    moment_x = sum(c["mass_kg"] * c["x_from_transom_m"] for c in manifest)
    moment_y = sum(c["mass_kg"] * c["y_transverse_m"] for c in manifest)
    moment_z = sum(c["mass_kg"] * c["z_from_keel_m"] for c in manifest)

    lcg = moment_x / total_mass
    tcg = moment_y / total_mass
    vcg = moment_z / total_mass

    return total_mass, lcg, tcg, vcg

def compute_moments_of_inertia(manifest, lcg, vcg):
    ixx = 0.0
    iyy = 0.0
    izz = 0.0

    for c in manifest:
        m = c["mass_kg"]
        dx = c["x_from_transom_m"] - lcg
        dy = c["y_transverse_m"]
        dz = c["z_from_keel_m"] - vcg

        ixx += m * (dy**2 + dz**2)
        iyy += m * (dx**2 + dz**2)
        izz += m * (dx**2 + dy**2)

    return ixx, iyy, izz

def analyze_planing_stability(total_mass, lcg, vcg, beam_m=1.18, speed_ms=16.67):
    rho = 1000.0
    g = 9.81
    delta_n = total_mass * g

    froude_beam = speed_ms / math.sqrt(g * beam_m)
    cl_0 = (2.0 * delta_n) / (rho * (speed_ms**2) * (beam_m**2))

    tau_est_deg = cl_0 / (0.012 * math.sqrt(cl_0) + 0.0055 * (froude_beam**2.5) / 100.0)
    tau_est_deg = max(1.5, min(5.5, tau_est_deg))

    deadrise_deg = 16.0
    deadrise_rad = math.radians(deadrise_deg)
    tau_crit_porpoising = (cl_0 / (0.0055 * math.cos(deadrise_rad))) ** 0.35 * 3.8
    tau_crit_porpoising = max(3.5, min(6.5, tau_crit_porpoising))
    porpoising_safe = (tau_est_deg < tau_crit_porpoising)

    decel_g = 0.5
    pitch_moment_decel = total_mass * (decel_g * g) * vcg
    restoring_moment_lever = lcg - 0.90
    bow_dive_safe = (restoring_moment_lever * delta_n) > (pitch_moment_decel * 1.5)

    return {
        "froude_beam": round(froude_beam, 2),
        "cl_0": round(cl_0, 4),
        "dynamic_trim_deg": round(tau_est_deg, 2),
        "critical_porpoising_trim_deg": round(tau_crit_porpoising, 2),
        "porpoising_safe": porpoising_safe,
        "bow_dive_safe": bow_dive_safe
    }

def run_analysis():
    data = load_metrology()
    manifest = data["component_mass_manifest"]

    mass, lcg, tcg, vcg = compute_center_of_gravity(manifest)
    ixx, iyy, izz = compute_moments_of_inertia(manifest, lcg, vcg)

    kb = data["hydrostatics"]["kb_m"]
    bm = data["hydrostatics"]["bm_m"]
    gm = kb + bm - vcg

    stability = analyze_planing_stability(mass, lcg, vcg)

    print("=====================================================")
    print("  TANDAV CI4 — HYDROSTATIC & METROLOGY CG REPORT     ")
    print("=====================================================")
    print(f"Total Wet Mass:          {mass:.1f} kg ({mass * 2.20462:.1f} lbs)")
    print(f"Longitudinal CG (LCG):   {lcg:.3f} m from transom (Target: 1.18 - 1.22m)")
    print(f"Transverse CG (TCG):     {tcg:.3f} m from centerline")
    print(f"Vertical CG (VCG):       {vcg:.3f} m above keel (Target: 0.18 - 0.22m)")
    print(f"Metacentric Height (GM): {gm:.3f} m (Min safe: 0.450m)")
    print("-----------------------------------------------------")
    print(f"Roll Inertia (Ixx):      {ixx:.2f} kg*m^2")
    print(f"Pitch Inertia (Iyy):     {iyy:.2f} kg*m^2")
    print(f"Yaw Inertia (Izz):       {izz:.2f} kg*m^2")
    print("-----------------------------------------------------")
    print(f"Froude Beam Number (Fn): {stability['froude_beam']}")
    print(f"Estimated Planing Trim:  {stability['dynamic_trim_deg']} deg")
    print(f"Porpoising Limit Trim:   {stability['critical_porpoising_trim_deg']} deg")
    print(f"Porpoising Suppression:  {'PASS (STABLE)' if stability['porpoising_safe'] else 'FAIL (TRIM TOO HIGH)'}")
    print(f"Bow-Diving Margin:       {'PASS (SAFE RECOVERY)' if stability['bow_dive_safe'] else 'FAIL (RISK OF SUBMERGENCE)'}")
    print("=====================================================")

    return {
        "mass_kg": mass,
        "lcg_m": lcg,
        "vcg_m": vcg,
        "gm_m": gm,
        "stability": stability
    }

if __name__ == "__main__":
    run_analysis()
