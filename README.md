# CNC-Press-Brake-Simulator


Under development


# CNC Press Brake Simulator (Gio)

Version: v0.4.0 (Pro Refactored)

## Description

This application is a desktop simulator for a CNC (Computer Numerical Control) Press Brake machine, built using the Go programming language and the Gio immediate mode GUI library. It allows users to define sheet metal properties, select tooling (punch and die), specify a sequence of bend operations, and simulate the bending process, visualizing a conceptual profile of the bent sheet.

The application is designed to be fully offline capable and incorporates considerations for robust input handling.

## Features

* **Sheet Metal Definition**: Specify length, thickness, width, and material for the workpiece.
* **Tooling Setup**: Select from a predefined list of punches and dies.
* **Bend Sequence Definition**: Add multiple bend steps, each with position, angle, radius, and direction.
* **Process Simulation**: Conceptually simulate the bending process based on the defined job.
* **Profile Visualization**: Generates a stub SVG file representing the sheet profile (actual rendering of complex bent profiles is a placeholder).
* **User-Friendly Interface**: GUI built with Gio, organized into collapsible accordion panels.
* **Status Updates**: Provides feedback to the user on actions and errors.
* **Dialogs**: Confirmation dialogs for critical actions like clearing bend sequences.
* **Offline First**: Designed to run without an internet connection.
* **Input Validation**: Includes checks for sensible input values for dimensions and bend parameters.

## Project Structure

The project is organized into several packages to separate concerns:



cnc_press_brake_gio/
├── go.mod                 # Go module definition
├── main.go                # Main application entry point
└── internal/
├── appcontroller/     # Contains the AppController UI logic, event handling, layouts
│   ├── controller.go
│   └── ui_utils.go    # UI helper functions (e.g., icon drawing)
├── config/            # Application-wide constants
│   └── config.go
├── models/            # Core data structures (SheetMetal, BendStep, Material)
│   └── models.go
├── tooling/           # Tooling definitions (Punch, Die, ToolingManager)
│   └── tooling.go
├── job/               # Job and JobController for domain logic
│   └── job.go
├── machine/           # PressBrake machine simulation logic
│   └── machine.go
└── export/            # Export functionalities (e.g., SVG generation)
└── export.go


## Prerequisites

* **Go**: Version 1.20 or later (as specified in `go.mod`, can be adjusted).
* **Gio Dependencies**: The necessary Gio libraries (e.g., `gioui.org v0.8.0` or your target version). These will be fetched by Go modules.
* **C Compiler**: Gio uses Cgo, so a C compiler (like GCC or Clang) needs to be installed and configured on your system.
    * **macOS**: Xcode Command Line Tools (`xcode-select --install`)
    * **Linux**: `gcc` or `clang` (e.g., `sudo apt install build-essential`)
    * **Windows**: A MinGW-w64 based toolchain (e.g., via MSYS2 or TDM-GCC).

## Setup and Running

1.  **Create Project Structure**:
    * Use the `setup_cnc_project.sh` script provided (if you have it) to automatically generate the directory structure and initial files.
        ```bash
        ./setup_cnc_project.sh
        ```
    * Alternatively, manually create the directories and files as outlined in the "Project Structure" section. Ensure the module name in `go.mod` and import paths match. The default module name used by the script is `cncpressbrakegio`.

2.  **Navigate to Project Directory**:
    ```bash
    cd cnc_press_brake_gio
    ```

3.  **Initialize/Tidy Go Modules**:
    If you created the project manually or changed the module name, initialize Go modules:
    ```bash
    go mod init <your_module_name> # e.g., go mod init cncpressbrakegio
    ```
    Then, or if you used the script, ensure all dependencies are downloaded and consistent:
    ```bash
    go mod tidy
    ```
    This command will download `gioui.org` and any other dependencies based on the `go.mod` file and import statements.

4.  **Run the Application**:
    ```bash
    go run main.go
    ```

5.  **(Optional) Build Executable**:
    To create a standalone executable:
    ```bash
    go build -o cnc_simulator main.go
    ./cnc_simulator
    ```

## Code Overview

* **`main.go`**: Entry point of the application. Initializes the Gio window and the `AppController`.
* **`internal/config`**: Defines global constants for the application, such as version, default window dimensions, and validation limits.
* **`internal/models`**: Contains the core data structures like `SheetMetal`, `MaterialDetails`, `BendStep`, and `BendDirection`.
* **`internal/tooling`**: Defines `Punch`, `Die`, and the `ToolingManager` for managing available tools.
* **`internal/job`**: Contains the `Job` structure (which holds a sheet and a sequence of bend steps) and the `JobController` for business logic related to managing jobs.
* **`internal/machine`**: Defines the `PressBrake` structure and its simulation logic (`ProcessJob`).
* **`internal/export`**: Handles data export, currently including a stub for `GenerateSVGProfile`.
* **`internal/appcontroller`**:
    * `controller.go`: The heart of the UI. The `AppController` struct manages the application's state, handles user events, and defines the layout for all UI components.
    * `ui_utils.go`: Contains helper functions for creating UI elements, like custom icons.

## Offline Capability & Security

* **Offline First**: The application is designed to run without an internet connection. All necessary assets like fonts (`gofont`) are embedded or generated.
* **Input Validation**: User inputs for dimensions, angles, and other parameters are validated against sensible ranges defined in `internal/config/config.go` to prevent crashes and maintain data integrity.
* **Secure Temporary Files**: Temporary files (like SVGs) are created using `os.MkdirTemp`, which is a secure way to handle temporary file storage.
* **No External Network Calls**: The core simulator does not make external network calls, reducing exposure to network-based vulnerabilities.

## Potential Future Enhancements

* Accurate 2D/3D visualization of the bent sheet metal profile.
* Implementation of bend allowance/deduction calculations (K-factor, Y-factor).
* Collision detection during the bend sequence.
* Saving and loading job definitions to/from files (with secure parsing).
* More extensive tooling library and management.
* Material library expansion with more detailed properties.
* User preferences and settings.

---

This README provides a starting point. Feel free to expand it as the project evolves!

