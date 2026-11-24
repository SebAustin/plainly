import PhotosUI
import SwiftUI

struct ComposerView: View {
  @Bindable var model: LetterViewModel
  @State private var photo: PhotosPickerItem?
  @FocusState private var isEditing: Bool

  var body: some View {
    Sheet {
      VStack(alignment: .leading, spacing: 14) {
        SectionLabel(text: "Step one")
        Text("The letter").font(Theme.display(30)).foregroundStyle(Theme.ink)

        ZStack(alignment: .topLeading) {
          if model.letterText.isEmpty {
            Text("Paste the letter here, or add a photo of it.")
              .font(.system(size: 14, design: .monospaced))
              .foregroundStyle(Theme.inkSoft.opacity(0.7))
              .padding(.top, 8)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
          TextEditor(text: $model.letterText)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .focused($isEditing)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
              // The keyboard covers the buttons, so it needs its own way out.
              ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
              }
            }
            .frame(minHeight: 170, maxHeight: 260)
            .accessibilityLabel("Letter text")
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }

        HStack(spacing: 10) {
          Button {
            isEditing = false
            Task { await model.explain() }
          } label: {
            if model.isReading {
              HStack(spacing: 8) { ProgressView().tint(Theme.sheet); Text("Reading…") }
            } else {
              Text("Explain this letter")
            }
          }
          .buttonStyle(InkButtonStyle())
          .disabled(!model.canExplain)

          PhotosPicker(selection: $photo, matching: .images) {
            if model.isRecognizing {
              HStack(spacing: 8) { ProgressView(); Text("Reading photo…") }
            } else {
              Text("Add a photo")
            }
          }
          .buttonStyle(InkButtonStyle(filled: false))
          .disabled(model.isRecognizing)
        }

        Button("Use a sample letter") { model.useSampleLetter() }
          .font(.subheadline)
          .underline()
          .foregroundStyle(Theme.ink)
          .frame(minHeight: 44)

        Text("A photo is turned into text on this device. The picture is never uploaded.")
          .font(.footnote)
          .foregroundStyle(Theme.inkSoft)
      }
    }
    .onChange(of: photo) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          await model.readPhoto(data)
        }
        photo = nil
      }
    }
  }
}
