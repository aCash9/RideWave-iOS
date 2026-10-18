import SwiftUI
import UIKit

struct RideContactsView: View {
    let close: () -> Void
    @StateObject private var model = RideContactsModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var pickerOpen = false
    @State private var interaction = 0
    @State private var switchControl = UIAccessibility.isSwitchControlRunning
    @GestureState private var touching = false

    private var timerPaused: Bool {
        scenePhase != .active || pickerOpen || model.calling || model.error != nil ||
        !model.loaded || editing || voiceOver || switchControl || touching
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { close() }
                VStack(spacing: 16) {
                    HStack {
                        Text("RIDE CONTACTS").font(.system(size: 11, weight: .bold))
                            .tracking(3).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !model.contacts.isEmpty {
                            Button(editing ? "Done" : "Edit") { interact(); editing.toggle() }
                                .frame(minWidth: 44, minHeight: 56)
                        }
                        Button(action: close) {
                            Image(systemName: "xmark").font(.title2).frame(width: 56, height: 56)
                        }.accessibilityLabel("Close contacts")
                    }
                    if !model.loaded {
                        Button("Retry loading contacts") { interact(); model.reload() }
                            .frame(minHeight: 56)
                    }
                    GeometryReader { area in
                        let entries = model.contacts.count + (model.contacts.count < 4 && model.loaded ? 1 : 0)
                        let landscape = geometry.size.width > geometry.size.height
                        let columns = max(1, landscape ? entries : min(entries, 2))
                        let diameter = min(entries == 1 ? 248.0 : 208.0,
                                           max(64, (area.size.width - CGFloat(columns - 1) * 20) / CGFloat(columns)))
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns), spacing: 24) {
                                ForEach(model.contacts) { contact in
                                    contactBubble(contact, diameter: diameter)
                                }
                                if model.contacts.count < 4 && model.loaded {
                                    Button {
                                        interact()
                                        pickerOpen = true
                                    } label: {
                                        VStack(spacing: 12) {
                                            Image(systemName: "plus").font(.system(size: 42))
                                            Text("Add contact").font(.subheadline).foregroundStyle(.secondary)
                                        }.frame(width: diameter, height: diameter)
                                            .overlay(Circle().stroke(.gray.opacity(0.6), lineWidth: 1))
                                            .contentShape(Circle())
                                    }.accessibilityLabel("Add contact")
                                }
                            }
                            .frame(minHeight: area.size.height, alignment: .center)
                        }
                    }
                }.padding(.horizontal, 24)
            }
        }
        .foregroundStyle(.white).buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .updating($touching) { _, touching, _ in touching = true }
            .onChanged { _ in interact() })
        .task(id: "\(interaction)-\(timerPaused)") {
            guard !timerPaused else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            close()
        }
        .onChange(of: scenePhase) {
            interact()
            if scenePhase == .active { model.returnedToApp() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            switchControl = UIAccessibility.isSwitchControlRunning
        }
        .sheet(isPresented: $pickerOpen, onDismiss: { interact() }) {
            ContactNumberPicker { result in
                pickerOpen = false
                interact()
                switch result {
                case .success(let contact):
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { model.add(contact) }
                case .failure(let error): model.error = error.localizedDescription
                }
            } cancelled: {
                pickerOpen = false
                interact()
            }
        }
        .alert("Ride contacts", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil; interact() } }
        )) {
            Button("OK") { model.error = nil; interact() }
        } message: { Text(model.error ?? "") }
    }

    private func interact() { interaction += 1 }

    private func contactBubble(_ contact: RideContact, diameter: CGFloat) -> some View {
        Button {
            interact()
            if editing {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { model.remove(contact) }
            } else { model.call(contact) }
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let data = contact.photo, let photo = UIImage(data: data) {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: diameter, height: diameter).clipShape(Circle())
                    } else {
                        Text(contact.name).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            .lineLimit(3).padding(20).frame(width: diameter, height: diameter)
                            .overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 1))
                    }
                    Image(systemName: editing ? "minus.circle.fill" : "phone.fill")
                        .font(.title2).padding(12).background(.black, in: Circle())
                }
                if contact.photo != nil {
                    Text(contact.name).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                }
            }.contentShape(Rectangle())
        }
        .disabled(model.calling)
        .accessibilityLabel(editing ? "Remove \(contact.name)" : "Call \(contact.name), \(contact.number)")
        .accessibilityHint(editing ? "Removes this saved ride contact" : "Opens the iOS call confirmation")
    }
}
