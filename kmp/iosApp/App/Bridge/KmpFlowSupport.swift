import Foundation
import MiGestorKit

// Helper for UI Scopes
class MainScope: CoroutineScope {
    let coroutineContext: KotlinCoroutineContext = Dispatchers.shared.Main
}

// MARK: - Flow to AsyncSequence Adapter

struct FlowAsyncSequence<T>: AsyncSequence {
    typealias Element = T
    let flow: Flow

    struct AsyncIterator: AsyncIteratorProtocol {
        private var streamIterator: AsyncStream<T>.Iterator

        init(flow: Flow) {
            let stream = AsyncStream<T> { continuation in
                flow.collect(collector: Collector { value in
                    if let element = value as? T {
                        continuation.yield(element)
                    }
                }) { error in
                    continuation.finish()
                }
            }
            self.streamIterator = stream.makeAsyncIterator()
        }

        mutating func next() async -> T? {
            await streamIterator.next()
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(flow: flow)
    }
}

class Collector: FlowCollector {
    let callback: (Any?) -> Void
    init(callback: @escaping (Any?) -> Void) {
        self.callback = callback
    }
    func emit(value: Any?, completionHandler: @escaping (Error?) -> Void) {
        callback(value)
        completionHandler(nil)
    }
}

extension Flow {
    func asAsyncSequence<T>(type: T.Type) -> FlowAsyncSequence<T> {
        FlowAsyncSequence(flow: self)
    }
}

extension RubricEvaluationTarget: @retroactive Identifiable {
    public var id: String {
        return "\(studentId)|\(columnId)"
    }
}

extension NotebookColumnDefinition: @retroactive Identifiable {}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
