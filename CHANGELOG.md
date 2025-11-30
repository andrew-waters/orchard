# Changelog

All notable changes to Orchard will be documented in this file.

## [0.6.1] - 2025-11-30

### Added
- 

### Changed
- 

### Fixed
- 


## [1.1.8]

### Added
- **Image Search and Download**: New feature to search Docker Hub for container images and download them directly from the UI
  - Search interface with Docker Hub integration
  - Pull progress tracking with visual feedback
  - Quick search suggestions for popular images (nginx, postgres, redis, alpine)
  - Displays official images with badges and star counts
  - Shows which images are already downloaded
  - Automatic image list refresh after successful pulls
- **Run Container from Image**: New feature to run containers directly from images with comprehensive configuration options
  - "Run Container" button in image detail view and search results
  - Configuration dialog with tabbed interface for easy navigation
  - Basic settings: container name, detached mode, auto-remove options
  - Port mappings: map container ports to host ports with TCP/UDP protocol selection
  - Volume mounts: bind mount host directories into containers with read-only option
  - Environment variables: set custom environment variables
  - Advanced options: working directory and command override
- **Delete Images**: Added ability to delete downloaded images
  - "Delete" button in image detail view (only shown if image is not in use)
  - Context menu delete option in image list
  - Safety check: prevents deletion if image is in use by any container
  - Confirmation dialog before deletion
- **Edit Container Configuration**: Added ability to edit stopped containers
  - "Edit Configuration" button appears for stopped containers
  - Pre-filled configuration dialog with all current settings
  - Edit ports, volumes, environment variables, working directory, and commands
  - Container is automatically deleted and recreated with new settings
  - Warning banner explains the recreation process
- **Terminal Attachment**: Added ability to attach terminal to running containers
  - "Terminal" button with dropdown menu in toolbar for running containers
  - Choose between sh (default shell) or bash
  - Opens in Terminal.app with interactive session
  - Context menu option to open terminal from container list

### Changed
- **Settings page deprecated**: You can not access them in the main window
  - Loading state now displays to prevent jarring view changes
  - We now required `0.6.0` and check the CLI version for compatibility

### Fixed
- Fixed image commands to use correct CLI syntax for container 0.6.0 (`container image pull` and `container image list` instead of plural `images`)


## [1.1.7] - 2025-11-08

Note this should have been 0.1.7 but was incorrectly tagged.

### Added
- 

### Changed
- 

### Fixed
- 


## [0.1.5] - 2025-06-19

### Added
- 

### Changed
- 

### Fixed
- 


## [0.1.4] - 2025-06-18

### Added
- 

### Changed
- 

### Fixed
- 


## [0.1.3] - 2025-06-18

### Added
- 

### Changed
- 

### Fixed
- 


## [0.1.2] - 2025-06-18

### Added
- 

### Changed
- 

### Fixed
- 


## [0.1.1] - 2025-06-18

### Added
- 

### Changed
- 

### Fixed
- 


## [0.1.0] - 2025-06-18

### Added
- Initial release

### Changed
-

### Fixed
-
