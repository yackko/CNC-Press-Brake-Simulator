#!/bin/bash

# Script to create the folder and file structure for the CNC Press Brake Gio application.

PROJECT_NAME="cnc_press_brake_gio"
MODULE_NAME="cncpressbrakegio" # Go module name (usually github.com/user/repo)

# Create root project directory
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME" || exit

echo "Creating project structure in $(pwd)..."

# Create go.mod file
cat <<EOF >go.mod
module ${MODULE_NAME}

go 1.20 // Or your desired Go version (e.g., 1.18, 1.21)

require gioui.org v0.8.0 // Or your target Gio version
EOF

# Create main.go
mkdir -p .
cat <<EOF >main.go
package main

import (
	"log"
	"os"

	"gioui.org/app" // If 'undefined', check Gio setup
	"gioui.org/unit"

	"${MODULE_NAME}/internal/appcontroller"
	"${MODULE_NAME}/internal/config"
)

func main() {
	go func() {
		// If app.NewWindow is undefined, your Go environment is not resolving 'gioui.org/app'.
		// Please verify your Go module setup (go.mod, \`go mod tidy\`, GOPATH/GOROOT).
		win := app.NewWindow(
			app.Title(config.AppName+" "+config.AppVersion),
			app.Size(unit.Dp(config.DefaultWindowWidthDp), unit.Dp(config.DefaultWindowHeightDp)),
		)

		controller, err := appcontroller.NewAppController(win)
		if err != nil {
			log.Fatalf("Failed to initialize AppController: %v", err)
		}

		if err := controller.Loop(); err != nil { // Renamed from loop to Loop for export
			log.Fatalf("Error in application loop: %v", err)
		}
		os.Exit(0)
	}()
	app.Main() // This must be called from the main goroutine.
}
EOF

# Create internal directory structure
mkdir -p internal/appcontroller
mkdir -p internal/config
mkdir -p internal/models
mkdir -p internal/tooling
mkdir -p internal/job
mkdir -p internal/machine
mkdir -p internal/export

# Create internal/config/config.go
cat <<EOF >internal/config/config.go
package config

// Application-wide constants
const (
	AppName    = "CNC Press Brake Simulator"
	AppVersion = "v0.4.0 (Pro Refactored)" // Updated version

	DefaultWindowWidthDp  float32 = 1200
	DefaultWindowHeightDp float32 = 800

	MinSheetDimension float64 = 0.1   // Minimum allowed dimension for sheet metal (e.g., 0.1mm)
	MaxSheetDimension float64 = 10000.0 // Maximum allowed dimension (e.g., 10m)
	MinBendRadius     float64 = 0.0   // Minimum bend radius (0 can mean sharp)
	MaxBendRadius     float64 = 500.0 // Sensible upper limit for bend radius
	MinBendAngle      float64 = 1.0   // Min bend angle (exclusive 0)
	MaxBendAngle      float64 = 179.0 // Max bend angle (exclusive 180)
)
EOF

# Create internal/models/models.go
cat <<EOF >internal/models/models.go
package models

import (
	"fmt"
	"log"
)

// MaterialName defines a type for material identifiers.
type MaterialName string

// Material constants
const (
	SteelMaterial     MaterialName = "Steel"
	AluminumMaterial  MaterialName = "Aluminum"
	StainlessMaterial MaterialName = "Stainless Steel"
	CopperMaterial    MaterialName = "Copper"
	MildSteelMaterial MaterialName = "Mild Steel"
)

// MaterialDetails holds properties of a specific material.
type MaterialDetails struct {
	Name                MaterialName
	Density             float64 // kg/m^3
	YieldStress         float64 // MPa
	TensileModulus      float64 // GPa (Young's Modulus)
	MinBendRadiusFactor float64 // Factor times thickness for MINIMUM recommended bend radius.
}

// BendDirection indicates the direction of the bend relative to the sheet.
type BendDirection string

const (
	BendDirectionUp   BendDirection = "Up"   // Material is bent upwards.
	BendDirectionDown BendDirection = "Down" // Material is bent downwards.
)

// BendStep defines a single bend operation in a job.
type BendStep struct {
	SequenceOrder int           // 1-based order of this bend in the job.
	Position      float64       // Distance from the reference edge to the bend line (mm).
	TargetAngle   float64       // Desired internal angle of the bend (degrees).
	Radius        float64       // Desired inner bend radius (mm).
	Direction     BendDirection // Direction of the bend.
}

// SheetMetal represents the workpiece.
type SheetMetal struct {
	ID             string
	OriginalLength float64 // mm
	Thickness      float64 // mm
	Width          float64 // mm
	Material       MaterialDetails
	CurrentBends   []BendStep // Represents the formed state of the sheet.
}

// NewSheetMetal creates a new sheet metal object.
func NewSheetMetal(id string, length, width, thickness float64, material MaterialDetails) (*SheetMetal, error) {
	if id == "" {
		return nil, fmt.Errorf("sheet ID cannot be empty")
	}
	if length <= 0 || width <= 0 || thickness <= 0 {
		return nil, fmt.Errorf("sheet dimensions must be positive (L:%.2f, W:%.2f, T:%.2f)", length, width, thickness)
	}
	if material.Name == "" {
		return nil, fmt.Errorf("material must be specified for sheet '%s'", id)
	}
	return &SheetMetal{
		ID:             id,
		OriginalLength: length,
		Width:          width,
		Thickness:      thickness,
		Material:       material,
		CurrentBends:   make([]BendStep, 0),
	}, nil
}

// ResetForm clears any applied bends, effectively making the sheet flat again.
func (s *SheetMetal) ResetForm() {
	s.CurrentBends = make([]BendStep, 0)
	log.Printf("INFO: Sheet '%s' form reset (bends cleared).", s.ID)
}

// GetMinBendRadius calculates the recommended minimum bend radius for the sheet's material and thickness.
func (s *SheetMetal) GetMinBendRadius() float64 {
	if s.Thickness <= 0 { return 0 } 
	if s.Material.MinBendRadiusFactor <= 0 {
		return s.Thickness * 0.5 // Default fallback
	}
	return s.Thickness * s.Material.MinBendRadiusFactor
}

// DefaultMaterials provides a basic set of materials.
var DefaultMaterials = map[MaterialName]MaterialDetails{
	SteelMaterial:     {Name: SteelMaterial, Density: 7850, YieldStress: 250, TensileModulus: 200, MinBendRadiusFactor: 1.5},
	AluminumMaterial:  {Name: AluminumMaterial, Density: 2700, YieldStress: 100, TensileModulus: 70, MinBendRadiusFactor: 1.0},
	StainlessMaterial: {Name: StainlessMaterial, Density: 8000, YieldStress: 215, TensileModulus: 193, MinBendRadiusFactor: 2.0},
	CopperMaterial:    {Name: CopperMaterial, Density: 8960, YieldStress: 70, TensileModulus: 117, MinBendRadiusFactor: 0.8},
	MildSteelMaterial: {Name: MildSteelMaterial, Density: 7850, YieldStress: 220, TensileModulus: 200, MinBendRadiusFactor: 1.2},
}

// GetMaterialNames returns a slice of material names for UI selection, in a preferred order.
func GetMaterialNames(mats map[MaterialName]MaterialDetails) []string {
	names := make([]string, 0, len(mats))
	preferredOrder := []MaterialName{SteelMaterial, AluminumMaterial, StainlessMaterial, CopperMaterial, MildSteelMaterial}
	added := make(map[MaterialName]bool)

	for _, nameKey := range preferredOrder {
		if _, ok := mats[nameKey]; ok {
			names = append(names, string(nameKey))
			added[nameKey] = true
		}
	}
	for nameKey := range mats { 
		if !added[nameKey] {
			names = append(names, string(nameKey))
		}
	}
	return names
}
EOF

# Create internal/tooling/tooling.go
cat <<EOF >internal/tooling/tooling.go
package tooling

// Punch represents the upper tool of the press brake.
type Punch struct {
	Name   string
	Height float64 // mm
	Angle  float64 // degrees, e.g., 88, 90, 30
	Radius float64 // mm, tip radius of the punch
}

// Die represents the lower tool (V-die) of the press brake.
type Die struct {
	Name           string
	VOpening       float64 // mm, width of the V-opening
	Angle          float64 // degrees, angle of the V
	ShoulderRadius float64 // mm, radius of the die shoulders
}

// ToolingManager manages the available punches and dies.
type ToolingManager struct {
	punches map[string]*Punch // Map of punch name to Punch struct
	dies    map[string]*Die   // Map of die name to Die struct
}

// NewToolingManager creates a new tooling manager with some default tools.
func NewToolingManager() *ToolingManager {
	return &ToolingManager{
		punches: map[string]*Punch{
			"P88.10.R06":    {Name: "P88.10.R06", Height: 60, Angle: 88, Radius: 0.6},
			"P30.15.R1":     {Name: "P30.15.R1", Height: 65, Angle: 30, Radius: 1.0},
			"Default Punch": {Name: "Default Punch", Height: 50, Angle: 90, Radius: 1.0},
		},
		dies: map[string]*Die{
			"D12.90.R2":   {Name: "D12.90.R2", VOpening: 12, Angle: 90, ShoulderRadius: 2.0},
			"D20.60.R3":   {Name: "D20.60.R3", VOpening: 20, Angle: 60, ShoulderRadius: 3.0},
			"Default Die": {Name: "Default Die", VOpening: 16, Angle: 90, ShoulderRadius: 2.0},
		},
	}
}

func (m *ToolingManager) GetPunchNames() []string {
	names := make([]string, 0, len(m.punches))
	for name := range m.punches { names = append(names, name) }
	return names
}
func (m *ToolingManager) GetDieNames() []string {
	names := make([]string, 0, len(m.dies))
	for name := range m.dies { names = append(names, name) }
	return names
}
func (m *ToolingManager) GetPunchByName(name string) (*Punch, bool) { p, ok := m.punches[name]; return p, ok }
func (m *ToolingManager) GetDieByName(name string) (*Die, bool)   { d, ok := m.dies[name]; return d, ok }

func (m *ToolingManager) GetDefaultPunch() *Punch {
	if p, ok := m.GetPunchByName("Default Punch"); ok { return p }
	for _, p := range m.punches { return p } 
	return nil
}
func (m *ToolingManager) GetDefaultDie() *Die {
	if d, ok := m.GetDieByName("Default Die"); ok { return d }
	for _, d := range m.dies { return d } 
	return nil
}
EOF

# Create internal/job/job.go
cat <<EOF >internal/job/job.go
package job

import (
	"fmt"
	"log"

	"${MODULE_NAME}/internal/models" // Use module name for internal imports
)

// Job represents a set of operations to be performed on a sheet metal.
type Job struct {
	Name  string
	Sheet *models.SheetMetal // The workpiece for this job.
	Steps []*models.BendStep // The sequence of bend operations.
}

// NewJob creates a new job with a given name and sheet.
func NewJob(name string, sheet *models.SheetMetal) (*Job, error) {
	if name == "" { return nil, fmt.Errorf("job name cannot be empty") }
	if sheet == nil { return nil, fmt.Errorf("job must have a sheet defined") }
	return &Job{
		Name:  name,
		Sheet: sheet,
		Steps: make([]*models.BendStep, 0),
	}, nil
}

// JobController manages job-related operations (domain logic).
type JobController struct {
	currentJob *Job
}

func NewJobController() *JobController { return &JobController{} }
func (jc *JobController) GetCurrentJob() *Job { return jc.currentJob }
func (jc *JobController) SetCurrentJob(job *Job) { jc.currentJob = job }

// AddBendStepToCurrentJob adds a new bend step to the currently active job.
func (jc *JobController) AddBendStepToCurrentJob(pos, angle, radius float64, dir models.BendDirection) (*models.BendStep, error) {
	if jc.currentJob == nil { return nil, fmt.Errorf("no current job selected") }
	if jc.currentJob.Sheet == nil { return nil, fmt.Errorf("current job has no sheet defined") }
	
	// Validation against sheet dimensions should happen here or in a dedicated validation service.
	// For now, basic check.
	if pos <= 0 || pos >= jc.currentJob.Sheet.OriginalLength {
		return nil, fmt.Errorf("bend position (%.2fmm) is outside sheet length (0-%.2fmm)", pos, jc.currentJob.Sheet.OriginalLength)
	}

	step := &models.BendStep{
		SequenceOrder: len(jc.currentJob.Steps) + 1,
		Position:      pos,
		TargetAngle:   angle,
		Radius:        radius,
		Direction:     dir,
	}
	jc.currentJob.Steps = append(jc.currentJob.Steps, step)
	log.Printf("INFO: Domain: Added bend step %d to job '%s'", step.SequenceOrder, jc.currentJob.Name)
	return step, nil
}

// ClearBendStepsFromCurrentJob removes all bend steps from the current job.
func (jc *JobController) ClearBendStepsFromCurrentJob() error {
	if jc.currentJob == nil { return fmt.Errorf("no current job to clear steps from") }
	jc.currentJob.Steps = make([]*models.BendStep, 0)
	if jc.currentJob.Sheet != nil {
		jc.currentJob.Sheet.ResetForm()
	}
	log.Printf("INFO: Domain: Cleared all bend steps from job '%s'.", jc.currentJob.Name)
	return nil
}
EOF

# Create internal/machine/machine.go
cat <<EOF >internal/machine/machine.go
package machine

import (
	"fmt"
	"log"

	"${MODULE_NAME}/internal/job"    // Use module name
	"${MODULE_NAME}/internal/models"  // Use module name
	"${MODULE_NAME}/internal/tooling" // Use module name
)

// PressBrake represents the (simulated) CNC machine.
type PressBrake struct {
	Name                  string
	currentPunch          *tooling.Punch
	currentDie            *tooling.Die
	totalPartsBentSession int
}

func NewPressBrake(name string, punch *tooling.Punch, die *tooling.Die) *PressBrake {
	return &PressBrake{Name: name, currentPunch: punch, currentDie: die}
}
func (pb *PressBrake) SetPunch(p *tooling.Punch) {
	pb.currentPunch = p
	log.Printf("INFO: Machine: PressBrake '%s' punch set to: '%s'", pb.Name, p.Name)
}
func (pb *PressBrake) SetDie(d *tooling.Die) {
	pb.currentDie = d
	log.Printf("INFO: Machine: PressBrake '%s' die set to: '%s'", pb.Name, d.Name)
}
func (pb *PressBrake) GetCurrentPunch() *tooling.Punch { return pb.currentPunch }
func (pb *PressBrake) GetCurrentDie() *tooling.Die   { return pb.currentDie }

// ProcessJob simulates the bending process for a given job.
func (pb *PressBrake) ProcessJob(j *job.Job) (*models.SheetMetal, error) {
	if j == nil || j.Sheet == nil { return nil, fmt.Errorf("job or sheet is nil") }
	if pb.currentPunch == nil || pb.currentDie == nil { return nil, fmt.Errorf("tooling not set") }

	log.Printf("INFO: Machine: PressBrake '%s' processing job '%s' (%d steps). Punch: '%s', Die: '%s'.",
		pb.Name, j.Name, len(j.Steps), pb.currentPunch.Name, pb.currentDie.Name)

	j.Sheet.ResetForm() // Start with a flat sheet

	for i, step := range j.Steps {
		log.Printf("  Machine Sim: Step %d/%d: Bend at %.2fmm, Angle %.2f°, Radius %.2fmm, Dir %s",
			i+1, len(j.Steps), step.Position, step.TargetAngle, step.Radius, step.Direction)
		j.Sheet.CurrentBends = append(j.Sheet.CurrentBends, *step)
	}

	pb.totalPartsBentSession++
	log.Printf("INFO: Machine: Job '%s' processed. Total parts bent this session: %d", j.Name, pb.totalPartsBentSession)
	return j.Sheet, nil
}
func (pb *PressBrake) GetTotalPartsBentSession() int { return pb.totalPartsBentSession }
EOF

# Create internal/export/export.go
cat <<EOF >internal/export/export.go
package export

import (
	"fmt"
	"log"
	"os"
	"strings"

	"${MODULE_NAME}/internal/models" // Use module name
)

// GenerateSVGProfile creates a simplified SVG representation of the sheet's profile.
func GenerateSVGProfile(sheet *models.SheetMetal, filePath string) error {
	if sheet == nil { return fmt.Errorf("sheet is nil for SVG generation") }

	svgWidth := sheet.OriginalLength + 40 
	svgHeight := 100.0

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("<svg width=\"%.1f\" height=\"%.1f\" xmlns=\"http://www.w3.org/2000/svg\" style=\"background-color: #f8f9fa; border: 1px solid #dee2e6; font-family: sans-serif;\">\n", svgWidth, svgHeight))
	sb.WriteString(fmt.Sprintf("  <title>Profile: %s</title>\n", sheet.ID))
	sb.WriteString("  <defs><style>.info-text { font-size: 10px; fill: #495057; } .sheet-rect { fill: #e9ecef; stroke: #adb5bd; stroke-width: 0.5; }</style></defs>\n")
	
	sheetDisplayHeight := sheet.Thickness * 8 
	if sheetDisplayHeight < 5 { sheetDisplayHeight = 5 }
	if sheetDisplayHeight > 40 { sheetDisplayHeight = 40 }
	sb.WriteString(fmt.Sprintf("  <rect x=\"20\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" class=\"sheet-rect\" />\n", (svgHeight-sheetDisplayHeight)/2, sheet.OriginalLength, sheetDisplayHeight))
	
	sb.WriteString(fmt.Sprintf("  <text x=\"10\" y=\"15\" class=\"info-text\">Sheet ID: %s (Stub SVG)</text>\n", sheet.ID))
	sb.WriteString(fmt.Sprintf("  <text x=\"10\" y=\"30\" class=\"info-text\">L:%.1f, W:%.1f, T:%.1f, Material: %s</text>\n", sheet.OriginalLength, sheet.Width, sheet.Thickness, sheet.Material.Name))
	sb.WriteString(fmt.Sprintf("  <text x=\"10\" y=\"%.1f\" class=\"info-text\">Bends Defined: %d</text>\n", svgHeight-10, len(sheet.CurrentBends)))
	sb.WriteString("</svg>\n")

	log.Printf("INFO: Export: Generating SVG profile for sheet '%s' to '%s'.", sheet.ID, filePath)
	err := os.WriteFile(filePath, []byte(sb.String()), 0644)
	if err != nil {
		log.Printf("ERROR: Export: Failed to write SVG file '%s': %v", filePath, err)
		return fmt.Errorf("writing SVG profile: %w", err)
	}
	return nil
}
EOF

# Create internal/appcontroller/ui_utils.go
cat <<EOF >internal/appcontroller/ui_utils.go
package appcontroller

import (
	"image"
	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget/material"
)

// downArrowIcon returns a widget that draws a downward-pointing triangle.
func downArrowIcon(th *material.Theme) layout.Widget {
	return func(gtx layout.Context) layout.Dimensions {
		sz := gtx.Dp(unit.Dp(12)) // Icon size
		var p clip.Path
		p.Begin(gtx.Ops)
		p.MoveTo(layout.FPt(image.Pt(0, sz/4)))          // Top-left
		p.LineTo(layout.FPt(image.Pt(sz, sz/4)))         // Top-right
		p.LineTo(layout.FPt(image.Pt(sz/2, sz*3/4)))     // Bottom-middle
		p.Close()
		
		stateOp := clip.Outline{Path: p.End()}.Op().Push(gtx.Ops)
		paint.ColorOp{Color: th.Palette.Fg}.Add(gtx.Ops)
		paint.PaintOp{}.Add(gtx.Ops)
		stateOp.Pop()
		return layout.Dimensions{Size: image.Pt(X: sz, Y: sz)}
	}
}

// upArrowIcon returns a widget that draws an upward-pointing triangle.
func upArrowIcon(th *material.Theme) layout.Widget {
	return func(gtx layout.Context) layout.Dimensions {
		sz := gtx.Dp(unit.Dp(12)) // Icon size
		var p clip.Path
		p.Begin(gtx.Ops)
		p.MoveTo(layout.FPt(image.Pt(0, sz*3/4)))      // Bottom-left
		p.LineTo(layout.FPt(image.Pt(sz, sz*3/4)))     // Bottom-right
		p.LineTo(layout.FPt(image.Pt(sz/2, sz/4)))     // Top-middle
		p.Close()

		stateOp := clip.Outline{Path: p.End()}.Op().Push(gtx.Ops)
		paint.ColorOp{Color: th.Palette.Fg}.Add(gtx.Ops)
		paint.PaintOp{}.Add(gtx.Ops)
		stateOp.Pop()
		return layout.Dimensions{Size: image.Pt(X: sz, Y: sz)}
	}
}

// formRow is a helper widget function to create a consistent label-widget row.
func (ac *AppController) formRow(label string, widgetFn layout.Widget) layout.Widget {
	return func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Alignment: layout.Baseline}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := material.Label(ac.th, ac.th.TextSize, label)
				return layout.Inset{Right: unit.Dp(8)}.Layout(gtx, lbl.Layout)
			}),
			layout.Flexed(1, widgetFn),
		)
	}
}
EOF

# Create internal/appcontroller/controller.go
# This will be a large file, containing the AppController struct and all its methods.
# The content is taken from the "gio_cnc_press_brake_v3_professional" document,
# adjusted for the new package structure.

cat <<EOF >internal/appcontroller/controller.go
package appcontroller

import (
	"fmt"
	"image"
	"image/color"
	"image/draw"
	_ "image/jpeg" 
	_ "image/png"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"gioui.org/app"
	"gioui.org/font/gofont"
	"gioui.org/io/key"
	"gioui.org/io/system"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/text"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	// Internal package imports using the defined module name
	"${MODULE_NAME}/internal/config"
	"${MODULE_NAME}/internal/models"
	"${MODULE_NAME}/internal/tooling"
	"${MODULE_NAME}/internal/job"
	"${MODULE_NAME}/internal/machine"
	"${MODULE_NAME}/internal/export"
)

// AppController manages the overall application state and UI logic.
type AppController struct {
	win *app.Window
	th  *material.Theme

	pressBrake     *machine.PressBrake // Changed to machine.PressBrake
	currentJob     *job.Job            // Changed to job.Job
	jobController  *job.JobController  // Changed to job.JobController
	toolingManager *tooling.ToolingManager // Changed to tooling.ToolingManager
	materials      map[models.MaterialName]models.MaterialDetails // Changed to models.MaterialName and models.MaterialDetails

	sheetLengthEditor    widget.Editor
	sheetThicknessEditor widget.Editor
	sheetWidthEditor     widget.Editor
	bendPositionEditor   widget.Editor
	bendAngleEditor      widget.Editor
	bendRadiusEditor     widget.Editor

	materialSelectClick  widget.Clickable
	selectedMaterialIdx  int
	materialNames        []string
	punchSelectClick     widget.Clickable
	selectedPunchIdx     int
	punchNames           []string
	dieSelectClick       widget.Clickable
	selectedDieIdx       int
	dieNames             []string
	bendDirectionClick   widget.Clickable
	selectedDirectionIdx int
	bendDirections       []string

	bendList          widget.List
	toolingStatusText string
	partsBentText     string
	statusText        string
	statusColor       color.NRGBA

	profileImage     image.Image
	profileImagePath string
	profileImageErr  error
	profileImageOp   paint.ImageOp

	tempDir         string
	accordionStates map[string]*AccordionItemState
	clickables      map[string]*widget.Clickable
	uiUpdate        chan struct{}
	statusTimer     *time.Timer
	statusClearLock sync.Mutex

	showDialog          bool
	dialogTitle         string
	dialogMessage       string
	dialogConfirmAction func()
	dialogCancelAction  func()
	dialogConfirmBtn    widget.Clickable
	dialogCancelBtn     widget.Clickable
}

// AccordionItemState holds state for a collapsible UI panel.
type AccordionItemState struct {
	Title    string
	Expanded bool
	Click    widget.Clickable
	Content  layout.Widget
}

// NewAppController initializes the main application controller.
func NewAppController(win *app.Window) (*AppController, error) {
	tmpDir, err := os.MkdirTemp("", "cnc_pressbrake_gio_")
	if err != nil {
		return nil, fmt.Errorf("failed to create temporary directory: %w", err)
	}
	log.Printf("INFO: Temporary directory for files: %s", tmpDir)

	mats := models.GetDefaultMaterials() // Use models package
	toolMgr := tooling.NewToolingManager() // Use tooling package
	defaultPunch := toolMgr.GetDefaultPunch()
	defaultDie := toolMgr.GetDefaultDie()

	if defaultPunch == nil || defaultDie == nil {
		log.Println("Warning: Default tooling not fully available from ToolingManager.")
	}

	pb := machine.NewPressBrake(config.AppName, defaultPunch, defaultDie) // Use machine package
	jc := job.NewJobController() // Use job package

	initialMaterialName := models.SteelMaterial 
	initialMaterial, matOk := mats[initialMaterialName]
	if !matOk {
		log.Printf("Warning: Default material '%s' not found. Using first available.", initialMaterialName)
		for _, m := range mats { initialMaterial = m; break }
		if initialMaterial.Name == "" { return nil, fmt.Errorf("no materials defined in default set") }
	}

	initialSheet, err := models.NewSheetMetal("DefaultSheet-001", 300.0, 100.0, 2.0, initialMaterial)
	if err != nil { return nil, fmt.Errorf("failed to create initial sheet: %w", err) }
	
	currentJobInstance, err := job.NewJob("DefaultJob-001", initialSheet) // Use job package
	if err != nil { return nil, fmt.Errorf("failed to create initial job: %w", err) }
	jc.SetCurrentJob(currentJobInstance)

	materialNames := models.GetMaterialNames(mats)
	punchNames := toolMgr.GetPunchNames()
	dieNames := toolMgr.GetDieNames()

	th := material.NewTheme()
	fontCollection := gofont.Collection()
	th.Shaper = text.NewShaper(text.WithCollection(fontCollection))

	ac := &AppController{
		win:            win,
		th:             th,
		pressBrake:     pb,
		jobController:  jc,
		currentJob:     currentJobInstance,
		toolingManager: toolMgr,
		materials:      mats,
		tempDir:        tmpDir,
		materialNames:  materialNames,
		punchNames:     punchNames,
		dieNames:       dieNames,
		bendDirections: []string{string(models.BendDirectionUp), string(models.BendDirectionDown)}, // Use models package
		bendList:       widget.List{},
		uiUpdate:       make(chan struct{}, 1),
		clickables:     make(map[string]*widget.Clickable),
	}

	ac.sheetLengthEditor.SetText(fmt.Sprintf("%.1f", currentJobInstance.Sheet.OriginalLength))
	ac.sheetThicknessEditor.SetText(fmt.Sprintf("%.1f", currentJobInstance.Sheet.Thickness))
	ac.sheetWidthEditor.SetText(fmt.Sprintf("%.1f", currentJobInstance.Sheet.Width))

	ac.selectedMaterialIdx = 0
	for i, name := range ac.materialNames { if name == string(currentJobInstance.Sheet.Material.Name) { ac.selectedMaterialIdx = i; break } }
	if len(ac.materialNames) == 0 { ac.selectedMaterialIdx = -1 }

	ac.selectedPunchIdx = 0
	if defaultPunch != nil { for i, name := range ac.punchNames { if name == defaultPunch.Name { ac.selectedPunchIdx = i; break } } }
	if len(ac.punchNames) == 0 { ac.selectedPunchIdx = -1 }

	ac.selectedDieIdx = 0
	if defaultDie != nil { for i, name := range ac.dieNames { if name == defaultDie.Name { ac.selectedDieIdx = i; break } } }
	if len(ac.dieNames) == 0 { ac.selectedDieIdx = -1 }
	
	ac.selectedDirectionIdx = 0

	ac.accordionStates = map[string]*AccordionItemState{
		"Sheet Properties":          {Title: "Sheet Properties", Expanded: true, Content: ac.layoutSheetPanel},
		"Tooling Setup":             {Title: "Tooling Setup", Expanded: true, Content: ac.layoutToolingPanel},
		"Define Bend Step":          {Title: "Define Bend Step", Expanded: true, Content: ac.layoutBendDefinitionPanel},
		"Current Job Bend Sequence": {Title: "Current Job Bend Sequence", Expanded: true, Content: ac.layoutBendSequencePanel},
	}

	ac.updateToolingStatusDisplay()
	ac.updatePartsBentDisplay()
	ac.updateStatus("System Initialized. Ready.", false)

	return ac, nil
}

func (ac *AppController) getOrCreateClickable(name string) *widget.Clickable {
	if _, ok := ac.clickables[name]; !ok {
		ac.clickables[name] = new(widget.Clickable)
	}
	return ac.clickables[name]
}

// Loop is the main event loop for the application window.
func (ac *AppController) Loop() error { // Renamed to Loop for export
	go func() {
		for range ac.uiUpdate { 
			ac.win.Invalidate()
		}
	}()

	var ops op.Ops
	for e := range ac.win.Events() {
		switch e := e.(type) {
		case system.DestroyEvent:
			ac.cleanup()
			log.Println("INFO: Application closing. DestroyEvent received.")
			return e.Err
		case system.FrameEvent:
			gtx := layout.NewContext(&ops, e)
			ac.processEvents(gtx)
			ac.Layout(gtx)
			e.Frame(gtx.Ops)
		case key.Event:
			if e.Name == key.NameEscape && e.State == key.Press {
				if ac.showDialog {
					ac.dismissDialog()
				} else {
					log.Println("INFO: Escape pressed, requesting window close.")
					ac.win.Perform(system.ActionClose)
				}
			}
		default:
			// log.Printf("Unhandled window event type: %T", e)
		}
	}
	return nil
}

func (ac *AppController) cleanup() {
	log.Println("INFO: Application closing. Cleaning up temporary directory...")
	if ac.tempDir != "" {
		err := os.RemoveAll(ac.tempDir)
		if err != nil {
			log.Printf("ERROR: Failed to remove temporary directory '%s': %v", ac.tempDir, err)
		} else {
			log.Printf("INFO: Successfully removed temporary directory: %s", ac.tempDir)
		}
	}
}

// Layout defines the overall UI structure. (Rest of the AppController methods follow)
// ... (SheetPanel, ToolingPanel, BendDefinitionPanel, BendSequencePanel, ExecutionPanel, ProfileDisplayPanel)
// ... (handleSheetUpdate, handleAddBendStep, handleClearBendSequence, handleExecuteBendProcess)
// ... (updateToolingStatusDisplay, updatePartsBentDisplay, updateStatus, signalUIUpdate, clearProfileImage, displayProfileImage, displayProfileSVG)
// ... (Dialog methods)

// --- Panel Layout Functions ---
// (These methods belong to AppController)

func (ac *AppController) Layout(gtx layout.Context) layout.Dimensions {
	splitterWidth := unit.Dp(1)
	mainUIDimensions := layout.Flex{Axis: layout.Horizontal}.Layout(gtx,
		layout.Flexed(0.4, ac.layoutLeftAccordion),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			size := image.Point{X: gtx.Dp(splitterWidth), Y: gtx.Constraints.Max.Y}
			rectState := clip.Rect{Max: size}.Push(gtx.Ops)
			paint.ColorOp{Color: ac.th.Palette.ContrastBg}.Add(gtx.Ops)
			paint.PaintOp{}.Add(gtx.Ops)
			rectState.Pop()
			return layout.Dimensions{Size: size}
		}),
		layout.Flexed(0.6, ac.layoutRightSide),
	)

	if ac.showDialog {
		paint.Fill(gtx.Ops, color.NRGBA{A: 0xCC}) 
		layout.Center.Layout(gtx, func(gtxDialog layout.Context) layout.Dimensions {
			gtxDialog.Constraints.Max.X = gtxDialog.Dp(450)
			if gtxDialog.Constraints.Max.X > gtx.Constraints.Max.X-gtx.Dp(40) {
				gtxDialog.Constraints.Max.X = gtx.Constraints.Max.X - gtx.Dp(40)
			}
			return ac.layoutDialog(gtxDialog)
		})
	}
	return mainUIDimensions
}

func (ac *AppController) layoutLeftAccordion(gtx layout.Context) layout.Dimensions {
	return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		items := []layout.FlexChild{
			layout.Rigid(ac.makeAccordionItem("Sheet Properties")),
			layout.Rigid(layout.Spacer{Height: unit.Dp(2)}.Layout),
			layout.Rigid(ac.makeAccordionItem("Tooling Setup")),
			layout.Rigid(layout.Spacer{Height: unit.Dp(2)}.Layout),
			layout.Rigid(ac.makeAccordionItem("Define Bend Step")),
			layout.Rigid(layout.Spacer{Height: unit.Dp(2)}.Layout),
			layout.Rigid(ac.makeAccordionItem("Current Job Bend Sequence")),
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, items...)
	})
}

func (ac *AppController) makeAccordionItem(title string) layout.Widget {
	return func(gtx layout.Context) layout.Dimensions {
		state, ok := ac.accordionStates[title]
		if !ok {
			log.Printf("Error: Accordion state for '%s' not found.", title)
			return layout.Dimensions{}
		}

		headerContentWidget := func(gtx layout.Context) layout.Dimensions {
			var iconWidget layout.Widget
			if state.Expanded { iconWidget = upArrowIcon(ac.th)
			} else { iconWidget = downArrowIcon(ac.th) }
			
			return layout.Flex{Alignment: layout.Middle, Spacing: layout.SpaceBetween}.Layout(gtx,
				layout.Rigid(material.Label(ac.th, ac.th.TextSize*1.1, title).Layout),
				layout.Rigid(iconWidget),
			)
		}

		clickableHeaderWithBorderStyle := func(gtx layout.Context) layout.Dimensions {
			return widget.Border{Color: ac.th.Palette.ContrastBg, Width: unit.Dp(0.5)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(6)).Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							return material.ButtonLayoutStyle{
								Button:     &state.Click,
								Background: ac.th.Palette.Bg,
							}.Layout(gtx, headerContentWidget)
						},
					)
				},
			)
		}

		flexChildren := []layout.FlexChild{ layout.Rigid(clickableHeaderWithBorderStyle) }
		if state.Expanded {
			contentLayoutWidget := func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4), Left: unit.Dp(8), Right: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, state.Content)
			}
			flexChildren = append(flexChildren, layout.Rigid(contentLayoutWidget))
		}
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx, flexChildren...)
	}
}

func (ac *AppController) layoutRightSide(gtx layout.Context) layout.Dimensions {
	return layout.UniformInset(unit.Dp(4)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(ac.layoutExecutionPanel),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{Top: unit.Dp(4), Bottom: unit.Dp(4)}.Layout(gtx, ac.layoutProfileDisplayPanel)
			}),
			layout.Rigid(ac.layoutStatusLabel),
		)
	})
}

func (ac *AppController) layoutSheetPanel(gtx layout.Context) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical, Spacing: layout.SpaceSides, Alignment: layout.Start}.Layout(gtx,
		layout.Rigid(ac.formRow("Length (mm):", material.Editor(ac.th, &ac.sheetLengthEditor, "e.g., 300.0").Layout)),
		layout.Rigid(ac.formRow("Thickness (mm):", material.Editor(ac.th, &ac.sheetThicknessEditor, "e.g., 2.0").Layout)),
		layout.Rigid(ac.formRow("Width (mm):", material.Editor(ac.th, &ac.sheetWidthEditor, "e.g., 100.0").Layout)),
		layout.Rigid(ac.formRow("Material:", func(gtx layout.Context) layout.Dimensions {
			text := "Select Material"; if len(ac.materialNames) > 0 && ac.selectedMaterialIdx >= 0 && ac.selectedMaterialIdx < len(ac.materialNames) { text = ac.materialNames[ac.selectedMaterialIdx] } else if len(ac.materialNames) == 0 { text = "No Materials" }
			return material.Button(ac.th, &ac.materialSelectClick, text).Layout(gtx)
		})),
		layout.Rigid(layout.Spacer{Height: unit.Dp(10)}.Layout),
		layout.Rigid(material.Button(ac.th, ac.getOrCreateClickable("updateSheetBtn"), "Update Sheet Properties").Layout),
	)
}

func (ac *AppController) layoutToolingPanel(gtx layout.Context) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical, Spacing: layout.SpaceSides}.Layout(gtx,
		layout.Rigid(material.Label(ac.th, ac.th.TextSize, "Select Punch:").Layout),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			text := "Select Punch"; if len(ac.punchNames) > 0 && ac.selectedPunchIdx >= 0 && ac.selectedPunchIdx < len(ac.punchNames) { text = ac.punchNames[ac.selectedPunchIdx] } else if len(ac.punchNames) == 0 { text = "No Punches" }
			return material.Button(ac.th, &ac.punchSelectClick, text).Layout(gtx)
		}),
		layout.Rigid(material.Label(ac.th, ac.th.TextSize, "Select Die:").Layout),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			text := "Select Die"; if len(ac.dieNames) > 0 && ac.selectedDieIdx >= 0 && ac.selectedDieIdx < len(ac.dieNames) { text = ac.dieNames[ac.selectedDieIdx] } else if len(ac.dieNames) == 0 { text = "No Dies" }
			return material.Button(ac.th, &ac.dieSelectClick, text).Layout(gtx)
		}),
		layout.Rigid(layout.Spacer{Height: unit.Dp(5)}.Layout),
		layout.Rigid(material.Label(ac.th, ac.th.TextSize, ac.toolingStatusText).Layout),
	)
}

func (ac *AppController) layoutBendDefinitionPanel(gtx layout.Context) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical, Spacing: layout.SpaceSides}.Layout(gtx,
		layout.Rigid(ac.formRow("Position (mm):", material.Editor(ac.th, &ac.bendPositionEditor, "e.g., 50.0").Layout)),
		layout.Rigid(ac.formRow("Target Angle (°):", material.Editor(ac.th, &ac.bendAngleEditor, "e.g., 90.0").Layout)),
		layout.Rigid(ac.formRow("Inner Radius (mm):", material.Editor(ac.th, &ac.bendRadiusEditor, "e.g., 2.0").Layout)),
		layout.Rigid(ac.formRow("Direction:", func(gtx layout.Context) layout.Dimensions {
			text := "Select Direction"; if len(ac.bendDirections) > 0 && ac.selectedDirectionIdx >= 0 && ac.selectedDirectionIdx < len(ac.bendDirections) { text = ac.bendDirections[ac.selectedDirectionIdx] }
			return material.Button(ac.th, &ac.bendDirectionClick, text).Layout(gtx)
		})),
		layout.Rigid(layout.Spacer{Height: unit.Dp(10)}.Layout),
		layout.Rigid(material.Button(ac.th, ac.getOrCreateClickable("addBendBtn"), "Add Bend Step to Job").Layout),
	)
}

func (ac *AppController) layoutBendSequencePanel(gtx layout.Context) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical, Spacing: layout.SpaceEnd}.Layout(gtx,
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			if ac.currentJob == nil || ac.currentJob.Steps == nil || len(ac.currentJob.Steps) == 0 { return material.Label(ac.th, ac.th.TextSize, "No bend steps defined.").Layout(gtx) }
			list := material.List(ac.th, &ac.bendList)
			return list.Layout(gtx, len(ac.currentJob.Steps), func(gtx layout.Context, i int) layout.Dimensions {
				if i < 0 || i >= len(ac.currentJob.Steps) { return layout.Dimensions{} }
				step := ac.currentJob.Steps[i]
				if step == nil { return material.Label(ac.th, ac.th.TextSize*0.9, "Error: Nil step data").Layout(gtx) }
				text := fmt.Sprintf("Step %d: Pos:%.1f, Ang:%.1f°, Rad:%.1f, Dir:%s", step.SequenceOrder, step.Position, step.TargetAngle, step.Radius, step.Direction)
				return layout.Inset{Top: unit.Dp(2), Bottom: unit.Dp(2), Left: unit.Dp(4), Right: unit.Dp(4)}.Layout(gtx, material.Label(ac.th, ac.th.TextSize*0.9, text).Layout)
			})
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layout.Inset{Top: unit.Dp(8)}.Layout(gtx, material.Button(ac.th, ac.getOrCreateClickable("clearBendsBtn"), "Clear All Bend Steps").Layout)
		}),
	)
}

func (ac *AppController) layoutExecutionPanel(gtx layout.Context) layout.Dimensions {
	return layout.Flex{Axis: layout.Vertical, Spacing: layout.SpaceAround, Alignment: layout.Middle}.Layout(gtx,
		layout.Rigid(material.Button(ac.th, ac.getOrCreateClickable("executeBtn"), "Run Bend Process").Layout),
		layout.Rigid(layout.Spacer{Height: unit.Dp(5)}.Layout),
		layout.Rigid(material.Label(ac.th, ac.th.TextSize, ac.partsBentText).Layout),
	)
}

func (ac *AppController) layoutProfileDisplayPanel(gtx layout.Context) layout.Dimensions {
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		if ac.profileImage != nil && ac.profileImageErr == nil {
			imgWidget := widget.Image{Src: ac.profileImageOp, Fit: widget.Contain}
			maxDim := gtx.Dp(400); imgConstraints := gtx.Constraints
			if imgConstraints.Max.X > maxDim { imgConstraints.Max.X = maxDim }
			if imgConstraints.Max.Y > maxDim { imgConstraints.Max.Y = maxDim }
			imgGtx := gtx; imgGtx.Constraints = imgConstraints
			return imgWidget.Layout(imgGtx)
		} else if ac.profileImageErr != nil { return material.Label(ac.th, ac.th.TextSize, "Error displaying profile: "+ac.profileImageErr.Error()).Layout(gtx)
		} else if ac.profileImagePath != "" { return material.Label(ac.th, ac.th.TextSize, "Profile: "+filepath.Base(ac.profileImagePath)+"\n(SVG rendering stubbed)").Layout(gtx) }
		return material.Label(ac.th, ac.th.TextSize, "Profile Display Area").Layout(gtx)
	})
}

func (ac *AppController) layoutStatusLabel(gtx layout.Context) layout.Dimensions {
	label := material.Label(ac.th, ac.th.TextSize*0.9, ac.statusText)
	label.Color = ac.statusColor; label.MaxLines = 2
	return layout.UniformInset(unit.Dp(4)).Layout(gtx, label.Layout)
}

func (ac *AppController) processEvents(gtx layout.Context) {
	for id, itemState := range ac.accordionStates {
		if itemState.Click.Clicked(gtx) { log.Printf("Accordion item '%s' toggled.", id); itemState.Expanded = !itemState.Expanded; ac.signalUIUpdate() }
	}
	if ac.materialSelectClick.Clicked(gtx) {
		if len(ac.materialNames) > 0 {
			ac.selectedMaterialIdx = (ac.selectedMaterialIdx + 1) % len(ac.materialNames)
			if ac.currentJob != nil && ac.currentJob.Sheet != nil {
				selectedMatName := models.MaterialName(ac.materialNames[ac.selectedMaterialIdx]) // Use models.MaterialName
				ac.currentJob.Sheet.Material = ac.materials[selectedMatName]
				ac.updateStatus(fmt.Sprintf("Material set to: %s", selectedMatName), false)
			}
		}
	}
	if ac.punchSelectClick.Clicked(gtx) {
		if len(ac.punchNames) > 0 {
			ac.selectedPunchIdx = (ac.selectedPunchIdx + 1) % len(ac.punchNames)
			if ac.toolingManager != nil && ac.pressBrake != nil && ac.selectedPunchIdx < len(ac.punchNames) {
				if punch, ok := ac.toolingManager.GetPunchByName(ac.punchNames[ac.selectedPunchIdx]); ok {
					ac.pressBrake.SetPunch(punch); ac.updateToolingStatusDisplay(); ac.updateStatus(fmt.Sprintf("Punch set to: %s", punch.Name), false)
				}
			}
		}
	}
	if ac.dieSelectClick.Clicked(gtx) {
		if len(ac.dieNames) > 0 {
			ac.selectedDieIdx = (ac.selectedDieIdx + 1) % len(ac.dieNames)
			if ac.toolingManager != nil && ac.pressBrake != nil && ac.selectedDieIdx < len(ac.dieNames) {
				if die, ok := ac.toolingManager.GetDieByName(ac.dieNames[ac.selectedDieIdx]); ok {
					ac.pressBrake.SetDie(die); ac.updateToolingStatusDisplay(); ac.updateStatus(fmt.Sprintf("Die set to: %s", die.Name), false)
				}
			}
		}
	}
	if ac.bendDirectionClick.Clicked(gtx) {
		if len(ac.bendDirections) > 0 { ac.selectedDirectionIdx = (ac.selectedDirectionIdx + 1) % len(ac.bendDirections); ac.updateStatus(fmt.Sprintf("Bend direction: %s", ac.bendDirections[ac.selectedDirectionIdx]), false) }
	}
	if ac.getOrCreateClickable("updateSheetBtn").Clicked(gtx) { ac.handleSheetUpdate() }
	if ac.getOrCreateClickable("addBendBtn").Clicked(gtx) { ac.handleAddBendStep() }
	if ac.getOrCreateClickable("clearBendsBtn").Clicked(gtx) { ac.handleClearBendSequence() }
	if ac.getOrCreateClickable("executeBtn").Clicked(gtx) { ac.handleExecuteBendProcess() }
	if ac.showDialog {
		if ac.dialogConfirmBtn.Clicked(gtx) { ac.dismissDialog(); if ac.dialogConfirmAction != nil { ac.dialogConfirmAction() } }
		if ac.dialogCancelBtn.Clicked(gtx) { ac.dismissDialog(); if ac.dialogCancelAction != nil { ac.dialogCancelAction() } }
	}
}

func (ac *AppController) handleSheetUpdate() {
	if ac.currentJob == nil || ac.currentJob.Sheet == nil { ac.updateStatus("No active job/sheet to update.", true); return }
	length, errL := strconv.ParseFloat(ac.sheetLengthEditor.Text(), 64)
	thickness, errT := strconv.ParseFloat(ac.sheetThicknessEditor.Text(), 64)
	width, errW := strconv.ParseFloat(ac.sheetWidthEditor.Text(), 64)
	if errL != nil || errT != nil || errW != nil { ac.updateStatus("Invalid sheet dimensions. Please use numbers.", true); return }
	if length < config.MinSheetDimension || length > config.MaxSheetDimension || 
	   thickness < config.MinSheetDimension || thickness > config.MaxSheetDimension || 
	   width < config.MinSheetDimension || width > config.MaxSheetDimension {
		ac.updateStatus(fmt.Sprintf("Sheet dimensions out of range (%.1f-%.1fmm).", config.MinSheetDimension, config.MaxSheetDimension), true); return
	}
	var selectedMaterialDetails models.MaterialDetails; ok := false
	if ac.selectedMaterialIdx >= 0 && ac.selectedMaterialIdx < len(ac.materialNames) {
		selectedMaterialName := models.MaterialName(ac.materialNames[ac.selectedMaterialIdx])
		selectedMaterialDetails, ok = ac.materials[selectedMaterialName]
		if !ok { ac.updateStatus(fmt.Sprintf("Selected material '%s' not found.", selectedMaterialName), true); return }
	} else { ac.updateStatus("No material selected or selection invalid.", true); return }
	
	// Recreate sheet if properties fundamentally change, or update existing
	newSheet, err := models.NewSheetMetal(ac.currentJob.Sheet.ID, length, width, thickness, selectedMaterialDetails)
	if err != nil { ac.updateStatus(fmt.Sprintf("Error updating sheet: %v", err), true); return }
	ac.currentJob.Sheet = newSheet
	ac.currentJob.Sheet.ResetForm() // Ensure bends are cleared as sheet props changed

	ac.clearProfileImage(); ac.updateStatus(fmt.Sprintf("Sheet properties updated for job '%s'.", ac.currentJob.Name), false)
}

func (ac *AppController) handleAddBendStep() {
	if ac.jobController == nil { ac.updateStatus("Job controller not initialized.", true); return }
	if ac.currentJob == nil || ac.currentJob.Sheet == nil { ac.updateStatus("Cannot add bend: No active job or sheet defined.", true); return }
	posStr := ac.bendPositionEditor.Text(); angleStr := ac.bendAngleEditor.Text(); radStr := ac.bendRadiusEditor.Text()
	pos, errP := strconv.ParseFloat(posStr, 64); angle, errA := strconv.ParseFloat(angleStr, 64); radius, errR := strconv.ParseFloat(radStr, 64)
	if errP != nil || errA != nil || errR != nil { ac.updateStatus("Invalid bend parameters. Ensure numbers.", true); return }
	
	direction := models.BendDirectionUp // Default
	if ac.selectedDirectionIdx >= 0 && ac.selectedDirectionIdx < len(ac.bendDirections) { 
		direction = models.BendDirection(ac.bendDirections[ac.selectedDirectionIdx]) 
	}

	if pos <= 0 || pos >= ac.currentJob.Sheet.OriginalLength { ac.updateStatus(fmt.Sprintf("Bend position %.1fmm outside sheet (0-%.1fmm).", pos, ac.currentJob.Sheet.OriginalLength), true); return }
	if radius < config.MinBendRadius || radius > config.MaxBendRadius { ac.updateStatus(fmt.Sprintf("Bend radius %.2fmm outside range (%.1f-%.1fmm).", radius, config.MinBendRadius, config.MaxBendRadius), true); return }
	if angle < config.MinBendAngle || angle > config.MaxBendAngle { ac.updateStatus(fmt.Sprintf("Bend angle %.1f° outside range (%.1f-%.1f°).", angle, config.MinBendAngle, config.MaxBendAngle), true); return }
	
	minSheetRadius := ac.currentJob.Sheet.GetMinBendRadius()
	addStepAction := func() {
		if _, err := ac.jobController.AddBendStepToCurrentJob(pos, angle, radius, direction); err != nil {
			ac.updateStatus(fmt.Sprintf("Failed to add bend step: %v", err), true)
		} else { ac.updateStatus("New bend step added to current job.", false) }
		ac.signalUIUpdate()
	}
	if radius > 1e-6 && radius < minSheetRadius {
		ac.showConfirmDialog("Radius Warning", fmt.Sprintf("Radius (%.2fmm) < recommended min (%.2fmm).\nMay cause cracking.\nAdd anyway?", radius, minSheetRadius), addStepAction, func() { ac.updateStatus("Bend addition cancelled.", false) })
	} else { addStepAction() }
}

func (ac *AppController) handleClearBendSequence() {
	if ac.jobController == nil { ac.updateStatus("Job controller not initialized.", true); return }
	if ac.currentJob == nil { ac.updateStatus("No active job to clear.", true); return }
	if len(ac.currentJob.Steps) == 0 { ac.updateStatus("No bend steps to clear.", false); return }
	ac.showConfirmDialog("Clear Bend Sequence", fmt.Sprintf("Remove all %d bend steps from job '%s'?", len(ac.currentJob.Steps), ac.currentJob.Name),
		func() {
			if err := ac.jobController.ClearBendStepsFromCurrentJob(); err != nil { ac.updateStatus(fmt.Sprintf("Failed to clear steps: %v", err), true)
			} else { ac.clearProfileImage(); ac.updateStatus(fmt.Sprintf("All steps cleared for '%s'.", ac.currentJob.Name), false) }
			ac.signalUIUpdate()
		}, nil)
}

func (ac *AppController) handleExecuteBendProcess() {
	if ac.pressBrake == nil { ac.updateStatus("Press brake not initialized.", true); return }
	if ac.currentJob == nil || ac.currentJob.Sheet == nil { ac.updateStatus("No job or sheet loaded.", true); return }
	if len(ac.currentJob.Steps) == 0 { ac.updateStatus("No bend steps to execute.", true); return }
	if ac.pressBrake.GetCurrentPunch() == nil || ac.pressBrake.GetCurrentDie() == nil { ac.updateStatus("Tooling not set. Select punch & die.", true); return }
	ac.updateStatus(fmt.Sprintf("Processing job '%s'...", ac.currentJob.Name), false)
	go func() {
		processedSheet, err := ac.pressBrake.ProcessJob(ac.currentJob)
		if err != nil {
			ac.statusText = fmt.Sprintf("Job Processing Error: %v", err); ac.statusColor = color.NRGBA{R:0xD0,G:0x20,B:0x20,A:0xFF}
			ac.profileImage = nil; ac.profileImageOp = paint.ImageOp{}; ac.signalUIUpdate(); return
		}
		ac.partsBentText = fmt.Sprintf("Parts Bent (Session): %d", ac.pressBrake.GetTotalPartsBentSession())
		if processedSheet == nil {
			ac.statusText = "Job processing returned nil sheet."; ac.statusColor = color.NRGBA{R:0xD0,G:0x20,B:0x20,A:0xFF}; ac.signalUIUpdate(); return
		}
		svgFileName := filepath.Join(ac.tempDir, fmt.Sprintf("profile_%s_%d.svg", processedSheet.ID, time.Now().UnixNano()))
		if svgErr := export.GenerateSVGProfile(processedSheet, svgFileName); svgErr != nil { // Use export package
			ac.statusText = fmt.Sprintf("SVG Generation Error: %v", svgErr); ac.statusColor = color.NRGBA{R:0xD0,G:0x20,B:0x20,A:0xFF}
			ac.profileImage = nil; ac.profileImageOp = paint.ImageOp{}
		} else {
			ac.profileImagePath = svgFileName
			ac.statusText = fmt.Sprintf("Job '%s' processed. Profile updated.", ac.currentJob.Name); ac.statusColor = color.NRGBA{R:0x20,G:0x80,B:0x20,A:0xFF}
		}
		ac.signalUIUpdate()
	}()
}

func (ac *AppController) updateToolingStatusDisplay() {
	punchName, dieName := "None", "None"
	if ac.pressBrake != nil { if p := ac.pressBrake.GetCurrentPunch(); p != nil { punchName = p.Name }; if d := ac.pressBrake.GetCurrentDie(); d != nil { dieName = d.Name } }
	ac.toolingStatusText = fmt.Sprintf("Active Tooling: Punch: %s, Die: %s", punchName, dieName); ac.signalUIUpdate()
}
func (ac *AppController) updatePartsBentDisplay() {
	if ac.pressBrake != nil { ac.partsBentText = fmt.Sprintf("Total Parts Bent (Session): %d", ac.pressBrake.GetTotalPartsBentSession())
	} else { ac.partsBentText = "Total Parts Bent (Session): N/A" }
	ac.signalUIUpdate()
}
func (ac *AppController) showConfirmDialog(title, message string, onConfirm, onCancel func()) {
	ac.dialogTitle = title; ac.dialogMessage = message; ac.dialogConfirmAction = onConfirm; ac.dialogCancelAction = onCancel
	ac.showDialog = true; ac.signalUIUpdate()
}
func (ac *AppController) dismissDialog() {
	ac.showDialog = false; ac.dialogConfirmAction = nil; ac.dialogCancelAction = nil; ac.signalUIUpdate()
}

func (ac *AppController) layoutDialog(gtx layout.Context) layout.Dimensions {
	dialogBackgroundColor := color.NRGBA{R: 0xFA, G: 0xFA, B: 0xFA, A: 0xFF}
	dialogBorderColor := color.NRGBA{R: 0xA0, G: 0xA0, B: 0xA0, A: 0xFF}
	return widget.Border{Color: dialogBorderColor, CornerRadius: unit.Dp(6), Width: unit.Dp(1)}.Layout(gtx,
		func(gtx layout.Context) layout.Dimensions {
			return layout.Stack{}.Layout(gtx,
				layout.Expanded(func(gtx layout.Context) layout.Dimensions {
					bounds := image.Rect(0, 0, gtx.Constraints.Min.X, gtx.Constraints.Min.Y)
					rectState := clip.Rect(bounds).Push(gtx.Ops); paint.ColorOp{Color: dialogBackgroundColor}.Add(gtx.Ops); paint.PaintOp{}.Add(gtx.Ops); rectState.Pop()
					return layout.Dimensions{Size: gtx.Constraints.Min}
				}),
				layout.Stacked(func(gtx layout.Context) layout.Dimensions {
					return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
						return layout.Flex{Axis: layout.Vertical, Spacing: layout.SpaceSides}.Layout(gtx,
							layout.Rigid(material.H6(ac.th, ac.dialogTitle).Layout),
							layout.Rigid(layout.Spacer{Height: unit.Dp(8)}.Layout),
							layout.Rigid(material.Body1(ac.th, ac.dialogMessage).Layout),
							layout.Rigid(layout.Spacer{Height: unit.Dp(16)}.Layout),
							layout.Rigid(func(gtx layout.Context) layout.Dimensions {
								return layout.Flex{Spacing: layout.SpaceAround, Alignment: layout.End}.Layout(gtx,
									layout.Flexed(1, func(gtx layout.Context) layout.Dimensions { return layout.Dimensions{} }),
									layout.Rigid(material.Button(ac.th, &ac.dialogCancelBtn, "Cancel").Layout),
									layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
									layout.Rigid(material.Button(ac.th, &ac.dialogConfirmBtn, "OK").Layout),
								)
							}),
						)
					})
				}),
			)
		})
}

EOF

echo "Project structure created successfully in ./${PROJECT_NAME}"
echo "Next steps:"
echo "1. cd ${PROJECT_NAME}"
echo "2. go mod tidy"
echo "3. go run main.go"
echo "If you encounter 'undefined' errors for Gio packages, please ensure your Go environment and Gio modules are correctly set up."
