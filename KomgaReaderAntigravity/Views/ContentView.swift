import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    // 4 Columns Grid (iPad/Desktop/Landscape) - User requested 4 columns
    let columns = Array(repeating: GridItem(.flexible(), spacing: 30), count: 4)
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Global Background: Blurred Cover (Random from cache)
                GeometryReader { geo in
                    Group {
                        // Use one cover from the stack covers if available
                        if let firstLib = appState.libraries.first,
                           let covers = appState.libraryStackCovers[firstLib.id],
                           let random = covers.first {
                            Image(uiImage: random)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .blur(radius: 20)
                                .opacity(0.3)
                        } else {
                            // Fallback Gradient
                             LinearGradient(gradient: Gradient(colors: [Color(red: 0.1, green: 0.1, blue: 0.2), .black]), startPoint: .top, endPoint: .bottom)
                        }
                    }
                }
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // MARK: - Zone 1: Server Header (Card Style)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .center, spacing: 15) {
                            // Icon
                            Image(systemName: "server.rack")
                                .font(.system(size: 30))
                                .foregroundColor(.green)
                                .shadow(color: .green.opacity(0.5), radius: 5)
                            
                            VStack(alignment: .leading) {
                                Text("Server Name") // FIXED: Matching Settings Field Label
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .textCase(.uppercase)
                                    .shadow(color: .black, radius: 2)
                                
                                Text(appState.serverName)
                                    .font(.title2)
                                    .bold()
                                    .foregroundColor(.white)
                                    .shadow(color: .black, radius: 2)
                            }
                            
                            Spacer()
                            
                            // Status
                            HStack(spacing: 12) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(appState.isLoadingLibraries ? Color.yellow : (appState.libraryError != nil ? Color.red : Color.green))
                                        .frame(width: 8, height: 8)
                                        .shadow(radius: 4)
                                    Text(appState.isLoadingLibraries ? "Connecting" : (appState.libraryError != nil ? "Off-Line" : "On-Line"))
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(appState.isLoadingLibraries ? Color.yellow : (appState.libraryError != nil ? Color.red : Color.green))
                                        .shadow(color: .black, radius: 2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                
                                Button(action: { appState.fetchLibraries() }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Circle().fill(Color.white.opacity(0.1)))
                                }
                            }
                        }
                        .padding()
                        .background(
                            ZStack {
                                // 1. Dark Base
                                Color(white: 0.15)
                                
                                // 2. Collage of Covers
                                GeometryReader { headerGeo in
                                    // Use first library's stack covers as source (random enough for header)
                                    // Or mix? Let's use whatever covers we have in appState.libraryCovers/Stack
                                    // Simple approach: Tiled covers
                                    HStack(spacing: 0) {
                                        ForEach(0..<6) { i in
                                            // Grab a random cover from any available
                                            let cover: UIImage? = {
                                                if let lib = appState.libraries.randomElement(),
                                                   let stack = appState.libraryStackCovers[lib.id],
                                                   let img = stack.randomElement() {
                                                    return img
                                                }
                                                return appState.libraryCovers.values.randomElement()
                                            }()
                                            
                                            if let img = cover {
                                                Image(uiImage: img)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: headerGeo.size.width / 6, height: headerGeo.size.height)
                                                    .clipped()
                                                    .opacity(0.4) // Transparent
                                            }
                                        }
                                    }
                                }
                                
                                // 3. Gradient Overlay for Text Readability
                                LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.4)], startPoint: .leading, endPoint: .trailing)
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 10)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)
                    }
                    .background(Color.clear)
                    
                    
                    // MARK: - Zone 2: Libraries Grid
                    ScrollView {
                        // Check for empty library list
                        if appState.isLoadingLibraries && appState.libraries.isEmpty {
                            VStack {
                                Spacer(minLength: 50)
                                ProgressView("Connecting to \(appState.serverName)...")
                                Spacer()
                            }
                        } else if appState.libraries.isEmpty {
                            VStack(spacing: 20) {
                                Spacer(minLength: 100)
                                Image(systemName: "books.vertical.circle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                Text("No libraries found.")
                                    .font(.title3)
                                    .foregroundColor(.gray)
                                Button("Refresh") { appState.fetchLibraries() }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 50) {
                                ForEach(appState.libraries) { library in
                                    NavigationLink(value: library) {
                                        LibraryImportCard(
                                            libraryName: library.name,
                                            covers: appState.libraryStackCovers[library.id] ?? []
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(30)
                            .padding(.bottom, 60)
                        }
                    }
                    .refreshable {
                        appState.fetchLibraries()
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Library.self) { library in
                SeriesListView(library: library)
            }
        }
        .task {
            // Auto-load on Launch via AppState
            appState.fetchLibraries()
        }
    }
}
