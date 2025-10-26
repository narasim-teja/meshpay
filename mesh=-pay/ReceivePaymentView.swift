//
//  ReceivePaymentView.swift
//  mesh=-pay
//
//  Display QR code and address for receiving payments
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReceivePaymentView: View {
    @EnvironmentObject var walletManager: WalletManager
    @Environment(\.dismiss) var dismiss
    @State private var showCopiedAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Scan to receive payment")
                    .font(.headline)
                    .padding(.top, 40)

                // QR Code
                if let qrImage = generateQRCode(from: walletManager.publicKey) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                }

                // Address
                VStack(spacing: 10) {
                    Text("Your Stellar Address")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(walletManager.publicKey)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Button(action: {
                    UIPasteboard.general.string = walletManager.publicKey
                    showCopiedAlert = true
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc.fill")
                        Text("Copy Address")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Receive XLM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Copied!", isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Address copied to clipboard")
            }
        }
    }

    func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    ReceivePaymentView()
        .environmentObject(WalletManager())
}
