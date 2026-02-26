/*

so we still occasionally get slow frames, this should not be happening in such a simple project.

From what I can tell this is occurring because of slow gpu or something which doesn't make too much
sense yet, it would be good to get a breakdown with nsight graphics to truly figure this out soon.

*/


#import "tbx/model_loading";
#import "tbx/geometry";
#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/movement";
#import "tbx/collision";
#import "tbx/math";
#import "tbx/engine";
#import "tbx/rectangle";
#import "tbx/physics";

#import "tbx/section_logger"()(false);

#import "Basic";
#import "GL";
#import "File";
#import "Random";
#import "Math";
#import "Window_Creation";
#import "GetRect";


Simp :: #import "Simp";
using,except(Shader) Simp;

Input :: #import "Input";

convert_obj_to_indexed_meshes :: (obj_data: *Obj_Data) -> [..] Indexed_Mesh {
    meshes: [..] Indexed_Mesh;
    
    for *obj_object : obj_data.all_objects {
        mesh: Indexed_Mesh;
        current_index: u32 = 0;
        
        for *face : obj_object.faces {
            if face.face_vertices.count < 3 continue;

            // now there are at least 3 vertices on this face.
            
            first_index := current_index;
            
            for *fv : face.face_vertices {
                array_add(*mesh.positions, obj_data.all_positions[fv.position_index]);
                
                // handle optional texture coordinates
                if fv.texture_coordinate_index >= 0 {
                    array_add(*mesh.texture_coordinates, obj_data.all_texture_coordinates[fv.texture_coordinate_index]);
                } else {
                    array_add(*mesh.texture_coordinates, .{0, 0});
                }
                
                // Handle optional normals
                if fv.normal_index >= 0 {
                    array_add(*mesh.normals, obj_data.all_normals[fv.normal_index]);
                } else {
                    array_add(*mesh.normals, .{0, 1, 0});  // default up normal
                }

                // this is temporary
                r1 := random_get_zero_to_one();
                r2 := random_get_zero_to_one();
                r3 := random_get_zero_to_one();
                random_color := Vector3.{r1, r2, r3};

                array_add(*mesh.rgb_colors, random_color);

                current_index += 1;
            }
            
            // fan triangulation (in case there are more than 3 verts on a face)
            for i : 1..face.face_vertices.count-2 {
                array_add(*mesh.indices, first_index);
                array_add(*mesh.indices, first_index + cast(u32) i);
                array_add(*mesh.indices, first_index + cast(u32) i + 1);
            }
        }
        
        array_add(*meshes, mesh);
    }
    
    return meshes;
}

Renderable :: struct {
    indexed_mesh : Indexed_Mesh;
    local_to_world_index : u32;
    render_object_index : u32;
};

Character :: struct {
    using #as cg : Collision_Geometry;
    using r : Renderable;
}

do_collision_simulation :: (windowed_program_3d : *Windowed_Program_3D, delta_time : float, velocity : *Vector3, on_ground : *bool,  character : *Character, map : Collision_Geometries, renderables: [] Renderable, movement_mode: Movement_Mode) {
    // this moves the character to the camera's position
    // windowed_program_3d.camera_per_object_transform_color_renderer.local_to_world_matrices[character_local_to_world_index] = make_translation_matrix4(windowed_program_3d.camera.position);

    // this is the character.
    // queue_render(*windowed_program_3d.camera_per_object_transform_color_renderer, character.render_object_index);
    for renderables queue_render(*windowed_program_3d.camera_per_object_transform_color_renderer, it.render_object_index);

    row_major := GL_TRUE;
    num_matrices_we_are_updating :u32 = 1;

    if (movement_mode == .GOD) {
        gmi := God_Mode_Input.{
            is_key_down (xx #char "E"),
            is_key_down (xx #char "Q"),
            is_key_down (xx #char "W"),
            is_key_down (xx #char "S"),
            is_key_down (xx #char "D"),
            is_key_down (xx #char "A"),
            is_key_down (xx #char " "),
            is_key_down (Input.Key_Code.SHIFT),
        }; 

        velocity.* = get_new_god_mode_velocity(velocity.*, get_forward(*windowed_program_3d.camera), gmi, delta_time);
    } 

    old_velocity := velocity.*;
    new_velocity : Vector3;
    if (movement_mode == .FPS) {

        fpmi := sample_first_person_movement_input();
        ground_state : Ground_State = ifx on_ground.* then .ON_GROUND else .IN_AIR;

        new_velocity = get_new_first_person_velocity(velocity.*, fpmi, get_forward(*windowed_program_3d.camera), delta_time, ground_state, Movement_Params.{acceleration_mpss = 20});
    }

    ellipsoid_radius := v3(0.4, 1.75 / 2, 0.4);  
    displacement := displacement_from_kinematic_update(old_velocity, new_velocity, delta_time);
    resolve_collisions_against_body_ellipsoid(map, ellipsoid_radius, *windowed_program_3d.camera.position, *displacement, on_ground);

    velocity.* = new_velocity;

    glUseProgram(windowed_program_3d.camera_per_object_transform_color_renderer.shader_program_gl_handle);

    Simp.update_window (windowed_program_3d.window);
    Simp.clear_render_target(.15, .08, .08, 1);

    glDepthMask (GL_TRUE);
    glEnable (GL_DEPTH_TEST);

    glClear (GL_DEPTH_BUFFER_BIT);

    render(*windowed_program_3d.camera_per_object_transform_color_renderer);

    context.simp.current_shader = null;
    render_tick_stats(windowed_program_3d);
    render_camera_stats(windowed_program_3d);

    swap_buffers(windowed_program_3d.window, false);
}


render_speed :: (using wp : *Windowed_Program, vel: Vector3) {
    label_theme := my_theme.label_theme;
    rect_height := 0.1;
    rect_width := 0.4;
    r_vel := get_rect_normalized(create_rectangle(-1, 1 - rect_height, rect_width, rect_height, .TOP_LEFT), xx window_width, xx window_height);

    horizontal_vel := vel;
    horizontal_vel.y = 0;

    label(r_vel, tprint("% m/s (h)", formatFloat(length(horizontal_vel), trailing_width=2, zero_removal=.NO)), *label_theme);
}

do_collision_simulation_cpma :: (windowed_program_3d: *Windowed_Program_3D, delta_time: float, movement_state: *CPMA_Movement_State, velocity: *Vector3, on_ground: *bool, map: Collision_Geometries, renderables: [] Renderable) {

    slog_scoped("do_collision_simulation_cpma");

    slog_start("0");

    for renderables queue_render(*windowed_program_3d.camera_per_object_transform_color_renderer, it.render_object_index);

    slog_end("0");
    slog_start("1");

    fpmi := sample_first_person_movement_input();

    update(movement_state, fpmi, *windowed_program_3d.camera.position, velocity, on_ground, get_forward(*windowed_program_3d.camera), *map, delta_time);

    // displacement := velocity.* * delta_time;

    // ellipsoid_radius := Vector3.{0.4, 1.75 / 2.0, 0.4};
    // resolve_collisions_against_body_ellipsoid(*map, ellipsoid_radius, *windowed_program_3d.camera.position, *displacement, on_ground);

    slog_end("1");
    slog_start("2");

    glUseProgram(windowed_program_3d.camera_per_object_transform_color_renderer.shader_program_gl_handle);

    Simp.update_window(windowed_program_3d.window);

    Simp.clear_render_target(.15, .08, .08, 1);

    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    glClear(GL_DEPTH_BUFFER_BIT);

    slog_end("2");
    slog_start("3");

    render(*windowed_program_3d.camera_per_object_transform_color_renderer);

    ctx := context;
    ctx.allocator = temp;

    slog_end("3");
    slog_start("4");

    push_context ctx {

        // crosshair
        raw_geom := create_annulus(ZERO3, Z3, 0.01, 0.02, 8); // todo assumes -z forward
        itpc := create_itpc_with_color(raw_geom, .{0.5, 0.8, 0.1});
        immediate_render(*windowed_program_3d.absolute_position_color_renderer, itpc.indices, itpc.positions, itpc.rgb_colors);

        dial_radius := 0.1;
        dial_border_thickness := 0.005;
        dial_color := Vector3.{0.5, 0.8, 0.1};

        // movement dial
        movement_dial_center := Vector2.{0.65, -0.8};
        movement_dial_geom := create_annulus(make_vector3(movement_dial_center, 0), Z3, dial_radius - dial_border_thickness, dial_radius, 8);
        movement_dial_itpc := create_itpc_with_color(movement_dial_geom, dial_color);
        immediate_render(*windowed_program_3d.absolute_position_color_renderer, movement_dial_itpc.indices, movement_dial_itpc.positions, movement_dial_itpc.rgb_colors);

        // movement input arrow
        forward : float = 0.0;
        right   : float = 0.0;
        if is_key_down(xx #char "W") forward += 1.0;
        if is_key_down(xx #char "S") forward -= 1.0;
        if is_key_down(xx #char "D") right   += 1.0;
        if is_key_down(xx #char "A") right   -= 1.0;

        input_dir := Vector2.{right, forward};
        input_len := length(input_dir);

        if input_len > 0.001 {
            normalized_dir := input_dir / input_len;
            clamped_len := min(input_len, 1.0);
            arrow_tip := movement_dial_center + normalized_dir * clamped_len * (dial_radius - dial_border_thickness);
            arrow_geom := create_2d_arrow(movement_dial_center, arrow_tip, 0.008);
            arrow_itpc := create_itpc_with_color(arrow_geom, dial_color);
            immediate_render(*windowed_program_3d.absolute_position_color_renderer, arrow_itpc.indices, arrow_itpc.positions, arrow_itpc.rgb_colors);
        }

        // todo also add the velocity to the dial, we want to use colors for this, where we go through a color spectrum, this allows people to get how fast they're going.

        // mouse dial
        mouse_dial_center := Vector2.{0.9, -0.8};
        mouse_dial_geom := create_annulus(make_vector3(mouse_dial_center, 0), Z3, dial_radius - dial_border_thickness, dial_radius, 8);
        mouse_dial_itpc := create_itpc_with_color(mouse_dial_geom, dial_color);
        immediate_render(*windowed_program_3d.absolute_position_color_renderer, mouse_dial_itpc.indices, mouse_dial_itpc.positions, mouse_dial_itpc.rgb_colors);

        // mouse delta arrow
        mouse_sensitivity_scale :: 10.0;
        mouse_dir := Vector2.{
            cast(float) windowed_program_3d.last_mouse_delta_x / mouse_sensitivity_scale,
           -cast(float) windowed_program_3d.last_mouse_delta_y / mouse_sensitivity_scale  // negate y: screen delta down is positive, but up should be positive on dial
        };
        mouse_len := length(mouse_dir);

        if mouse_len > 0.001 {
            normalized_mouse := mouse_dir / mouse_len;
            clamped_mouse_len := min(mouse_len, 1.0);
            mouse_arrow_tip := mouse_dial_center + normalized_mouse * clamped_mouse_len * (dial_radius - dial_border_thickness);
            mouse_arrow_geom := create_2d_arrow(mouse_dial_center, mouse_arrow_tip, 0.008);
            mouse_arrow_itpc := create_itpc_with_color(mouse_arrow_geom, dial_color);
            immediate_render(*windowed_program_3d.absolute_position_color_renderer, mouse_arrow_itpc.indices, mouse_arrow_itpc.positions, mouse_arrow_itpc.rgb_colors);
        }

    }

    slog_end("4");
    slog_start("5");


    slog_start("5.1");

    context.simp.current_shader = null;

    slog_end("5.1");
    slog_start("5.2");

    render_tick_stats(windowed_program_3d);

    slog_end("5.2");
    slog_start("5.3");

    render_speed(windowed_program_3d, velocity);

    slog_end("5.3");
    slog_start("5.4");

    render_camera_stats(windowed_program_3d);

    slog_end("5.4");
    slog_start("5.5");

    render_iteration(windowed_program_3d);

    slog_end("5.5");

    slog_end("5");
    slog_start("6");

    swap_buffers(windowed_program_3d.window, false);

    slog_end("6");
    slog_start("7");

    // We call glFinish() here to force the GPU to complete all queued work at a predictable point
    // in the frame. Without this, the GPU gradually falls behind the CPU over ~30 seconds (~4250
    // frames at 144fps), and then the driver forces a synchronization on whichever GL call happens
    // next — typically something innocuous like glGetUniformLocation or a Simp label() draw call —
    // causing a single ~200ms hitch before returning to normal.
    //
    // This happens because on Windows, the Desktop Window Manager (DWM) composites all windows
    // into the final display output. Even with vsync off, swap_buffers doesn't go directly to the
    // monitor — it goes into DWM's queue. Periodically DWM drains this queue, and the cost gets
    // pushed back onto our application as a stall on the next GL call that requires synchronization.
    //
    // glFinish() spreads that sync cost evenly across every frame (~0.5-1ms each) instead of letting
    // it accumulate into one large spike. Our busy-wait sleep_to_maintain_max_fps absorbs most of
    // this cost anyway since it's just waiting for the frame time budget to expire.
    //
    // An alternative fix is to use true exclusive fullscreen (via ChangeDisplaySettingsW with
    // CDS_FULLSCREEN), which bypasses DWM entirely. The current toggle_fullscreen implementation
    // only creates a borderless fullscreen window, which still composites through DWM.
    // Exclusive fullscreen is impractical during development due to slow alt-tabbing and crash
    // recovery issues, so glFinish() is the pragmatic solution for now.
    // glFinish();

    slog_end("7");

}

run_mesh_based_collision_program :: () {
    windowed_program_3d : Windowed_Program_3D;
    windowed_program_3d.movement_mode = .MANUAL;
    windowed_program_3d.camera_mode = .FIRST_PERSON;
    windowed_program_3d.window_width = 1000;
    windowed_program_3d.window_height = 1000;
    windowed_program_3d.window_name = "mwe_collision";

    
    windowed_program_3d.camera.offset = Y3 * 1.75 * 0.25;

    init(*windowed_program_3d);


    obj_data := load_obj("data/up_high.obj");
    // log("there were % objects", obj_data.all_objects.count);


    // obj_data := load_obj("data/under_and_over.obj");
    // obj_data := load_obj("data/gravity_test.obj");
    // just assuming that meshes live till the end of the program for now.
    meshes := convert_obj_to_indexed_meshes(*obj_data);

    map : Collision_Geometries;

    movement_mode := Movement_Mode.FPS;

    for meshes {
        cg : Collision_Geometry;
        cg.indexed_triangle_positions.indices = it.indices;
        cg.indexed_triangle_positions.positions = it.positions;


        cg.aabb = create_aabb_from_positions(cg.indexed_triangle_positions.positions);

        array_add(*map.indexed_triangle_positions,cg.indexed_triangle_positions);
        array_add(*map.aabbs,cg.aabb);
    }

    character : Character;
    character.indexed_triangle_positions = create_box(ZERO3, 0.4, 1.75, 0.4); 
    character.aabb = create_aabb_from_positions(character.indexed_triangle_positions.positions);
    character.indexed_mesh.indices = character.indexed_triangle_positions.indices;
    character.indexed_mesh.positions = character.indexed_triangle_positions.positions;

    for 1..character.indexed_mesh.positions.count array_add(*character.indexed_mesh.rgb_colors, .{0, .5, .5});

    character_local_to_world_index: u32;
    // character.render_object_index, character_local_to_world_index = buffer_object(*windowed_program_3d.camera_per_object_transform_color_renderer, character.indexed_mesh.indices, character.indexed_mesh.positions, character.indexed_mesh.rgb_colors);

    windowed_program_3d.camera.position = Y3 * 15;
    velocity : Vector3;
    on_ground : bool;

    movement_state : CPMA_Movement_State;

    renderables : [..] Renderable;
    
    count := 10;
    for meshes {
        renderable: Renderable;
        renderable.indexed_mesh = it;
        
        renderable.render_object_index, renderable.local_to_world_index = buffer_object(*windowed_program_3d.camera_per_object_transform_color_renderer, renderable.indexed_mesh.indices, renderable.indexed_mesh.positions, renderable.indexed_mesh.rgb_colors);

        array_add(*renderables, renderable);

        count += 1;
    }

    quit := false;
    while !windowed_program_3d.end_program {

        slog_scoped("tick");

        slog("iter: %", windowed_program_3d.iteration);

        slog_start("0");

        mark_frame_start(*windowed_program_3d);

        if is_key_just_pressed(xx #char "M")
            toggle_menu(*windowed_program_3d);

        per_frame_update(*windowed_program_3d);

        slog_end("0");

        slog_start("1");


        glUseProgram(windowed_program_3d.absolute_position_color_renderer.shader_program_gl_handle);
        set_aspect_ratio_uniform(*windowed_program_3d.absolute_position_color_renderer, .{xx windowed_program_3d.window_width, xx windowed_program_3d.window_height});
        glUseProgram(0);

        slog_end("1");



        if (windowed_program_3d.current_menu == .NONE) {
            slog_start("2");
            // do_collision_simulation(*windowed_program_3d, windowed_program_3d.delta_time, *velocity, *on_ground, *character, map, renderables, movement_mode);
            do_collision_simulation_cpma(*windowed_program_3d, windowed_program_3d.delta_time, *movement_state, *velocity, *on_ground, map, renderables);
            context.simp.current_shader = null; 
            slog_end("2");
        } else {
            slog_start("3");
            context.simp.current_shader = null;
            clear_render_target(.35, .35, .35, 1);
            render_menus(*windowed_program_3d.wp);
            // swap_buffers(windowed_program_3d.window, windowed_program_3d.vsync);
            swap_buffers(windowed_program_3d.window, false);
            slog_end("3");
        }

        slog_start("4");
        sleep_to_maintain_max_fps(*windowed_program_3d);
        slog_end("4");

        mark_frame_end(*windowed_program_3d);
    }
}

// this code is not being maintained rn
run_brush_based_collision_program :: () {
    windowed_program_3d : Windowed_Program_3D;
    windowed_program_3d.movement_mode = .MANUAL;
    windowed_program_3d.camera_mode = .THIRD_PERSON;
    windowed_program_3d.window_width = 1280;
    windowed_program_3d.window_height = 720;
    windowed_program_3d.window_name = "mwe_collision";

    init(*windowed_program_3d);

    map_content, success_read := read_entire_file("data/lair.map");
    if !success_read {
        log_error("Failed to read map file");
        return;
    }
    
    map, success := parse_map(map_content, .Y_UP, 0.05);
    if !success {
        log_error("Failed to parse map file");
        return;
    }

    // verifying normals
    for * entity : map.entities {
        for brush_idx : 0..entity.brushes.count-1 {
            brush := *entity.brushes[brush_idx];
            print("Brush %:\n", brush_idx);
            for plane_idx : 0..brush.planes.count-1 {
                plane := brush.planes[plane_idx];
                print("  Plane %: normal=(%, %, %) d=%\n", 
                      plane_idx, plane.normal.x, plane.normal.y, plane.normal.z, plane.d);
            }
        }
    }

    // convert map brushes to renderable mesh
    map_mesh := map_to_mesh_deduplicated(*map);

    movement_mode := Movement_Mode.GOD;

    // Create player using the new Player struct
    player : Player;
    player.position = .{ 0, 100, 0 };  // Start position (Y is up now, was {0, 0, 100})
    player.velocity = .{ 0, 0, 0 };
    player.radius = 0.2;   // Half of the old 0.4 width
    player.height = 1.75;

    // Create a visual representation for the player (cylinder approximated as box for now)
    player_mesh := create_box(ZERO3, player.radius * 2, player.height, player.radius * 2);
    
    player_indexed_mesh : Indexed_Mesh;
    player_indexed_mesh.indices = player_mesh.indices;
    player_indexed_mesh.positions = player_mesh.positions;
    
    player_local_to_world_indices : [..] u32;
    for 1..player_indexed_mesh.positions.count {
        array_add(*player_indexed_mesh.rgb_colors, .{random_get_zero_to_one(), random_get_zero_to_one(), random_get_zero_to_one()});
    }

    // player_render_object_index := buffer_object(
    //     *windowed_program_3d.camera_per_object_transform_color_renderer, 
    //     player_indexed_mesh.indices, 
    //     player_local_to_world_indices, 
    //     player_indexed_mesh.positions, 
    //     player_indexed_mesh.rgb_colors
    // );

    windowed_program_3d.camera.position = Y3 * 30;

    // create renderable for the map geometry
    renderables : [..] Renderable;
    
    renderable: Renderable;
    renderable.indexed_mesh.indices = map_mesh.indices;
    renderable.indexed_mesh.positions = map_mesh.positions;
    
    // generate colors for the map mesh
    for 1..renderable.indexed_mesh.positions.count {
        array_add(*renderable.indexed_mesh.rgb_colors, .{random_get_zero_to_one(), random_get_zero_to_one(), random_get_zero_to_one()});  // Gray color
    }
    
    renderable.render_object_index, renderable.local_to_world_index = buffer_object(
        *windowed_program_3d.camera_per_object_transform_color_renderer, 
        renderable.indexed_mesh.indices, 
        renderable.indexed_mesh.positions, 
        renderable.indexed_mesh.rgb_colors
    );
    
    array_add(*renderables, renderable);

    quit := false;
    while !windowed_program_3d.end_program {

        mark_frame_start(*windowed_program_3d);

        Input.update_window_events();
        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            getrect_handle_event(it);

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }
            }
        }

        if is_key_just_pressed(xx #char "M")
            toggle_menu(*windowed_program_3d);
    
        for Input.get_window_resizes() {
            Simp.update_window(it.window);  
            if it.window == windowed_program_3d.window {
                should_reinit := (it.width != windowed_program_3d.window_width) || (it.height != windowed_program_3d.window_height);

                windowed_program_3d.window_width  = it.width;
                windowed_program_3d.window_height = it.height;
            }
        }

        per_frame_update(*windowed_program_3d);

        if (windowed_program_3d.current_menu == .NONE) {


            gmi := God_Mode_Input.{
                is_key_down (xx #char "E"),
                is_key_down (xx #char "Q"),
                is_key_down (xx #char "W"),
                is_key_down (xx #char "S"),
                is_key_down (xx #char "D"),
                is_key_down (xx #char "A"),
                is_key_down (xx #char " "),
                is_key_down (Input.Key_Code.SHIFT),
            }; 

            player.velocity = get_new_god_mode_velocity(player.velocity, get_forward(*windowed_program_3d.camera), gmi, windowed_program_3d.delta_time);
            
            player.position += player.velocity * windowed_program_3d.delta_time;

            if !is_key_down( xx #char "C") {
                update_player(*player, *map, windowed_program_3d.delta_time);
            }
            
            player_transform := make_translation_matrix4(player.position);

            // player_transform._24 -= player.height / 2;
            
            // this moves the character to the camera's position
            // windowed_program_3d.camera_per_object_transform_color_renderer.local_to_world_matrices[0] = make_translation_matrix4(player.position);

            // queue_render(*windowed_program_3d.camera_per_object_transform_color_renderer, player_render_object_index);
            
            
            windowed_program_3d.camera.position = player.position;
            
            // this is just the map 
            for renderables queue_render(*windowed_program_3d.camera_per_object_transform_color_renderer, it.render_object_index);
            
            clear_render_target(.35, .35, .35, 1);  // Or whatever background color you want

            glDepthMask (GL_TRUE);
            glEnable (GL_DEPTH_TEST);

            glClear (GL_DEPTH_BUFFER_BIT);

            render(*windowed_program_3d.camera_per_object_transform_color_renderer);

            context.simp.current_shader = null;
            render_tick_stats(windowed_program_3d);

            // swap_buffers(windowed_program_3d.window, windowed_program_3d.vsync);
            swap_buffers(windowed_program_3d.window, false);


        } else {
            context.simp.current_shader = null;
            clear_render_target(.35, .35, .35, 1);
            render_menus(*windowed_program_3d.wp);
            swap_buffers(windowed_program_3d.window, false);
        }

        sleep_to_maintain_max_fps(*windowed_program_3d);
        mark_frame_end(*windowed_program_3d);
    }
}

main :: () {
    run_mesh_based_collision_program();
    // run_brush_based_collision_program();
    // test();
}











