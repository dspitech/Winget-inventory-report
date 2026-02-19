## Dynamic Winget Provisioning Engine (2026)

A Windows application inventory and provisioning engine built on **winget**, designed for modern admins, power users, and enterprise environments.

### ✨ Highlights

- **Modern HTML dashboard**
  - Full inventory of installed applications  
  - Dark, responsive design with key indicators (total apps, up-to-date, updates available)  
  - Instant search (name, ID, version) + status filter  

- **Smart pagination**
  - Table automatically paginated in **chunks of 50 applications**  
  - **Previous / Next** navigation with page indicator `Page X / Y`  
  - Fully compatible with search and filters (pagination recalculated after each filter)  

- **Interactive “Discovery & Provisioning” mode**
  - Console **WINGET DISCOVERY MODE** to explore and install apps  
  - Asks for an **application name** and/or a **predefined category** with examples  
  - Displays `winget search` results in a table and allows multi-selection  
  - Silent install (`--silent`) with agreements accepted (`--accept-*agreements`)  

- **IT / Ops oriented**
  - Reads install metadata from the registry (install date, etc.)  
  - Generates a **static HTML report** easy to archive or share  
  - Can be used on workstations, labs, PoCs, or as a base for a centralized inventory tool  

---

### 📂 Project structure

- `Provision.ps1`  
  Main PowerShell script:
  - Runs `winget list` and builds the in-memory inventory  
  - Generates `Inventory_Dashboard.html` with the dashboard and pagination  
  - Automatically opens the report in the default browser  
  - Then switches into **WINGET DISCOVERY MODE** (search + provisioning)  

- `Inventory_Dashboard.html`  
  - HTML file generated automatically by `Provision.ps1`  
  - No web server required: open directly in a browser  

- `dev-admin.dsc.yaml` (optional for your workflow)  
  - Configuration / infra file (DSC or other), usable in pipelines or admin environments.  

---

### 🚀 Requirements

- **OS**: Windows 10/11  
- **Shell**: PowerShell 7+ (recommended)  
- **Package manager**: `winget` installed and functional  
- Sufficient rights to install applications (for provisioning mode)  

---

### ▶️ Usage

#### 1. Clone the repository

```bash
git clone https://github.com/<your-account>/<your-repo>.git
cd <your-repo>
```

#### 2. Run the script

From PowerShell (preferably elevated):

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\Provision.ps1
```

#### 3. View the dashboard

- The script generates `Inventory_Dashboard.html` next to `Provision.ps1`.  
- Your default browser automatically opens the **System Inventory Dashboard**.  
- You can:
  - Search by **name**, **ID**, or **version**  
  - Filter by **status** (Up to date / Update available)  
  - Browse results in **pages of 50 items**  

#### 4. Use “WINGET DISCOVERY MODE”

At the end of the run, the script:

1. Shows a **category menu** with example applications.  
2. Asks you to choose a category **(or 0 for none)**.  
3. Optionally asks for an **application name**.  
4. Builds a combined search term (name + category hint) and runs `winget search`.  
5. Displays results and lets you install **one or more indexes** (`1,3,5`, etc.).  

---

### 🧱 Technical overview

- **Collection**
  - `winget list --accept-source-agreements`  
  - Regex-based parsing to split Name / ID / Version / Update info  
  - Registry lookups to retrieve **install dates** where possible  

- **HTML rendering**
  - HTML/CSS generated from PowerShell (heredoc strings)  
  - Modern styling (cards, badges, Font Awesome icons)  
  - Lightweight JS for:
    - Full-text search + status filter  
    - Pagination (50 items/page)  
    - Dynamic update of buttons and page indicator  

- **Provisioning**
  - `winget search` for discovery  
  - `winget install --id <ID> --silent --accept-package-agreements --accept-source-agreements`  
  - Basic error handling for invalid index input  

---

### 🧪 Typical use cases

- **Quick audit** of a workstation before migration or hardening  
- **Preparing a standard image** or baseline workstation (app profile)  
- **Troubleshooting**: quickly see which apps are outdated or missing  
- **Base layer** for an internal self-service application portal  

---

### 📌 Roadmap ideas

- Additional export formats (**CSV / JSON**)  
- Multi-machine support via **PowerShell remoting** or CI/CD pipelines  
- Richer categorization (tags, advanced filters in the dashboard)  
- “Dry-run” mode to simulate installs  
- Integration with Intune / GPO / MDM for advanced orchestration  

---

### 🤝 Contributing

Contributions are welcome:

- Bug fixes (parsing, locale/FR compatibility, etc.)  
- Dashboard design improvements (UX, accessibility)  
- New categories / provisioning scenarios  

Recommended workflow:

1. Create a feature branch.  
2. Clearly describe before/after behavior.  
3. Test the script on at least one Windows 10/11 machine with winget.  

---

### 📜 License

Add the license you want here (e.g. **MIT**, **Apache 2.0**, etc.).  

