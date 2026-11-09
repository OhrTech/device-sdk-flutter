allprojects {
    repositories {
        google()
        mavenCentral()
        // OHR_MAVEN_LOCAL: an unreleased net.ohrtech:device-sdk from ~/.m2 (publishToMavenLocal).
        if (System.getenv("OHR_MAVEN_LOCAL") != null) mavenLocal()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
