import AVFoundation
import PhotosUI
import SwiftUI
import TrustCore
import UIKit

/// Profile photo changes are staged locally and only uploaded when the person taps Save.
struct ProfileAvatarPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.trustPalette) private var palette

    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var previewImage: UIImage?
    @State private var selectedPreset: String?
    @State private var photoLoadGeneration = 0
    @State private var removeSelected = false
    @State private var isSaving = false
    @State private var isLoadingPhoto = false
    @State private var cameraPresented = false
    @State private var showingCameraAlert = false
    @State private var errorMessage: String?

    private let presetIDs = ["fern", "ember", "sky", "ocean", "sunrise", "lavender"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        stagedAvatar
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your picture")
                                .font(TrustTheme.display(22))
                                .foregroundStyle(palette.ink)
                            Text("Visible to people connected with you.")
                                .trustFont(12)
                                .foregroundStyle(palette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        TrustSectionHeading("Choose an icon")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 12)], spacing: 12) {
                            ForEach(presetIDs, id: \.self) { id in
                                Button { selectPreset(id) } label: {
                                    presetTile(id, selected: selectedPreset == id && !removeSelected && photoData == nil)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(ProfileAvatarArtwork.title(for: id)) icon")
                                .accessibilityAddTraits(selectedPreset == id && !removeSelected ? .isSelected : [])
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        TrustSectionHeading("Use a photo")
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Choose from Library", systemImage: "photo.on.rectangle")
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(TrustOutlineButtonStyle(compact: true))
                            .accessibilityIdentifier("avatar-choose-photo")

                            Button {
                                requestCamera()
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(TrustOutlineButtonStyle(compact: true))
                            .accessibilityIdentifier("avatar-take-photo")
                        }
                        if isLoadingPhoto {
                            ProgressView("Preparing photo…")
                                .trustFont(12)
                                .tint(palette.accent)
                        }
                    }

                    if model.you.avatar != nil {
                        Button("Remove picture", role: .destructive) {
                            invalidatePhotoLoad()
                            photoItem = nil
                            selectedPreset = nil
                            photoData = nil
                            previewImage = nil
                            removeSelected = true
                        }
                        .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                        .accessibilityIdentifier("avatar-remove")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .trustFont(12)
                            .foregroundStyle(palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("avatar-error")
                    }
                }
                .padding(TrustTheme.gutter)
                .trustReadableWidth()
            }
            .background(palette.paper.ignoresSafeArea())
            .navigationTitle("Profile picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TrustCopy.cancel) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges || isSaving || isLoadingPhoto)
                        .accessibilityIdentifier("avatar-save")
                }
            }
        }
        .task(id: photoItem) {
            guard let item = photoItem else {
                isLoadingPhoto = false
                return
            }
            photoLoadGeneration += 1
            let generation = photoLoadGeneration
            await loadPhoto(item, generation: generation)
        }
        .onDisappear {
            photoLoadGeneration += 1
            isLoadingPhoto = false
        }
        .sheet(isPresented: $cameraPresented) {
            CameraImagePicker { image in
                cameraPresented = false
                guard let image else { return }
                stage(image)
            }
            .ignoresSafeArea()
        }
        .alert("Camera unavailable", isPresented: $showingCameraAlert) {
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            Button(TrustCopy.cancel, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Allow camera access in Settings to take a picture.")
        }
        .task {
            if let selected = model.you.avatar?.knownPresetID { selectedPreset = selected }
        }
    }

    private var hasChanges: Bool {
        if removeSelected { return true }
        if photoData != nil { return true }
        guard let selectedPreset else { return false }
        return model.you.avatar?.knownPresetID != selectedPreset
    }

    @ViewBuilder
    private var stagedAvatar: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable().scaledToFill()
                .frame(width: 72, height: 72).clipShape(Circle())
        } else if let selectedPreset, !removeSelected {
            presetIcon(selectedPreset, size: 72)
        } else if removeSelected {
            TrustAvatar(name: model.you.displayName, seed: 0, size: 72, personID: model.you.id)
        } else {
            TrustAvatar(name: model.you.displayName, seed: 0, size: 72, avatar: model.you.avatar, personID: model.you.id)
        }
    }

    private func presetTile(_ id: String, selected: Bool) -> some View {
        VStack(spacing: 6) {
            presetIcon(id, size: 60)
            Text(ProfileAvatarArtwork.title(for: id))
                .trustFont(10, weight: .medium)
                .foregroundStyle(palette.muted)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? palette.accentSoft : palette.surface)
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? palette.accent : palette.line, lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func presetIcon(_ id: String, size: CGFloat) -> some View {
        return Image(ProfileAvatarArtwork.assetName(for: id))
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }

    private func selectPreset(_ id: String) {
        invalidatePhotoLoad()
        selectedPreset = id
        photoData = nil
        previewImage = nil
        photoItem = nil
        removeSelected = false
        errorMessage = nil
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem, generation: Int) async {
        isLoadingPhoto = true
        defer {
            if generation == photoLoadGeneration { isLoadingPhoto = false }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                guard isCurrentPhotoLoad(generation, item: item) else { return }
                errorMessage = "That photo could not be opened. Choose another one."
                photoItem = nil
                return
            }
            guard isCurrentPhotoLoad(generation, item: item) else { return }
            stage(image)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentPhotoLoad(generation, item: item) else { return }
            errorMessage = "That photo could not be opened. Choose another one."
            photoItem = nil
        }
    }

    private func stage(_ image: UIImage) {
        guard let data = AvatarPhotoEncoder.jpeg(image) else {
            errorMessage = "This photo could not be prepared. Choose another one."
            return
        }
        invalidatePhotoLoad()
        photoData = data
        previewImage = UIImage(data: data)
        selectedPreset = nil
        photoItem = nil
        removeSelected = false
        errorMessage = nil
    }

    private func isCurrentPhotoLoad(_ generation: Int, item: PhotosPickerItem) -> Bool {
        !Task.isCancelled && generation == photoLoadGeneration && photoItem == item
    }

    private func invalidatePhotoLoad() {
        photoLoadGeneration += 1
        isLoadingPhoto = false
    }

    @MainActor
    private func save() async {
        guard hasChanges else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let photoData {
                try await model.saveAvatarPhoto(photoData)
            } else if removeSelected {
                try await model.removeAvatar()
            } else if let selectedPreset {
                try await model.saveAvatar(presetID: selectedPreset)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestCamera() {
        // A photo selected earlier must not finish loading after the camera selection.
        invalidatePhotoLoad()
        photoItem = nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "A camera is not available on this device."
            showingCameraAlert = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPresented = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { cameraPresented = true }
                    else {
                        errorMessage = "Allow camera access in Settings to take a picture."
                        showingCameraAlert = true
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "Allow camera access in Settings to take a picture."
            showingCameraAlert = true
        @unknown default:
            errorMessage = "Camera access is unavailable."
            showingCameraAlert = true
        }
    }

}

private enum AvatarPhotoEncoder {
    static func jpeg(_ image: UIImage) -> Data? {
        let target = CGSize(width: 512, height: 512)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let normalized = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            let source = image.size
            guard source.width > 0, source.height > 0 else { return }
            let scale = max(target.width / source.width, target.height / source.height)
            let drawSize = CGSize(width: source.width * scale, height: source.height * scale)
            let rect = CGRect(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
            image.draw(in: rect)
        }
        for quality in [0.84, 0.72, 0.60, 0.48, 0.36] {
            if let data = normalized.jpegData(compressionQuality: quality), data.count <= 1_048_576 { return data }
        }
        return nil
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
