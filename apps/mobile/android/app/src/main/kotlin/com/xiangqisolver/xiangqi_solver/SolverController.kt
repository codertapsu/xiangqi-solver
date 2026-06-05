package com.xiangqisolver.xiangqi_solver

import java.util.concurrent.atomic.AtomicBoolean

/**
 * Single source of truth for "is Solver Mode running?". Both services and the
 * MethodChannel read this, so it lives in one small, testable place.
 */
object SolverController {

    private val running = AtomicBoolean(false)

    val isRunning: Boolean
        get() = running.get()

    fun setRunning(value: Boolean) {
        running.set(value)
    }
}
