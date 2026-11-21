import GarageVirtusKit
import SwiftData
import SwiftUI

/// Add, rename and delete Ryan's cars. Deleting a car deletes every part recorded for it.
struct CarsView: View {
    @Environment(GarageStore.self) private var garage
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Car.createdAt) private var cars: [Car]
    @State private var newName = ""
    @State private var carToDelete: Car?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cars").font(.title2.weight(.semibold))
            List {
                ForEach(cars) { car in
                    CarRow(car: car, onDelete: { carToDelete = car })
                }
            }
            .frame(minHeight: 200)
            HStack {
                TextField("Add a car, e.g. 2005 Honda S2000", text: $newName)
                    .onSubmit(addCar)
                Button("Add", action: addCar).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button("Done") { garage.save(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .confirmationDialog("Delete \(carToDelete?.name ?? "this car")?", isPresented: deleteBinding, presenting: carToDelete) { car in
            Button("Delete car and its parts", role: .destructive) { garage.delete(car) }
        } message: { _ in
            Text("Every part recorded for this car is deleted too.")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { carToDelete != nil }, set: { if !$0 { carToDelete = nil } })
    }

    private func addCar() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        garage.addCar(name: name, frame: "", variantID: "")
        newName = ""
    }
}

private struct CarRow: View {
    @Bindable var car: Car
    let onDelete: () -> Void

    var body: some View {
        HStack {
            TextField("Name", text: $car.name)
            TextField("Frame", text: $car.frame).frame(width: 90)
            Text("Parts: \(car.parts.count)").font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete car")
        }
    }
}
