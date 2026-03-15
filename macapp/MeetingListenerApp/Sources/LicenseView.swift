import SwiftUI

/// View for entering and validating license keys
struct LicenseView: View {
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var licenseKey = ""
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    // For development/testing
    @State private var showProductIdField = false
    @State private var productId = ""
    
    var onLicenseValidated: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Enter License Key")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Please enter your Gumroad license key to activate EchoPanel.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // Current status
            if licenseManager.state != .unknown {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(licenseManager.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            // License key input
            VStack(alignment: .leading, spacing: 8) {
                Text("License Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(.body, design: .monospaced))
                    .disabled(isValidating)
                    #if os(macOS)
                    .frame(width: 300)
                    #endif
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 40)
            
            // Product ID (for development)
            if showProductIdField {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Product ID (Development)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Gumroad Product ID", text: $productId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                        .disabled(isValidating)
                    
                    Text("This is only needed for testing. Production builds have this configured.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 40)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: validateLicense) {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text(isValidating ? "Validating..." : "Validate License")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKey.isEmpty || isValidating)
                
                #if DEBUG
                Button("Configure Product ID") {
                    productId = licenseManager.productId
                    showProductIdField.toggle()
                }
                .font(.caption)
                .buttonStyle(.link)
                #endif
                
                if licenseManager.state.isValid {
                    Button("Clear License") {
                        licenseManager.clearLicense()
                        licenseKey = ""
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    .foregroundColor(.red)
                }
            }
            .padding(.top, 10)
            
            // Help text
            VStack(spacing: 4) {
                Text("Don't have a license?")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("Purchase on Gumroad", destination: URL(string: "https://gumroad.com")!)
                    .font(.caption)
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .frame(minWidth: 400, minHeight: 450)
        .padding()
        .onAppear {
            productId = licenseManager.productId
        }
        .alert("License Validated", isPresented: $showSuccess) {
            Button("Continue") {
                onLicenseValidated?()
            }
        } message: {
            Text("Your license has been successfully validated. Thank you for purchasing EchoPanel!")
        }
    }
    
    private var statusColor: Color {
        switch licenseManager.state {
        case .valid:
            return .green
        case .invalid:
            return .red
        case .validating:
            return .yellow
        case .noLicense, .unknown:
            return .gray
        }
    }
    
    private func validateLicense() {
        guard !licenseKey.isEmpty else { return }
        
        isValidating = true
        errorMessage = nil
        
        // Update product ID if in development mode
        if showProductIdField && !productId.isEmpty {
            licenseManager.productId = productId
        }
        
        Task {
            do {
                let isValid = try await licenseManager.validateLicenseKey(licenseKey.trimmingCharacters(in: .whitespaces))
                
                await MainActor.run {
                    isValidating = false
                    if isValid {
                        showSuccess = true
                        errorMessage = nil
                    } else {
                        errorMessage = "Invalid license key. Please check and try again."
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LicenseView()
}
