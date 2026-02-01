#import "tbx/model_loading";
#import "tbx/geometry";
#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/movement";
#import "tbx/collision";
#import "tbx/math";
#import "tbx/engine";

#import "Basic";
#import "GL";
#import "Random";
#import "Math";
#import "Window_Creation";
#import "GetRect";
#import "Simp";

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
    local_to_world_indices : [..] u32;
    render_object_index : u32;
};

Character :: struct {
    using #as cg : Collision_Geometry;
    using r : Renderable;
}

do_collision_simulation :: (windowed_program_3d : *Windowed_Program_3D, delta_time : float, velocity : *Vector3, on_ground : *bool,  character : *Character, map : [] Collision_Geometry, renderables: [] Renderable, movement_mode: Movement_Mode) {
    // this moves the character to the camera's position
    windowed_program_3d.per_object_transform_renderer.local_to_world_matrices[0] = make_translation_matrix4(windowed_program_3d.camera.position);

    // this is the character.
    queue_render(*windowed_program_3d.per_object_transform_renderer, character.render_object_index);
    for renderables queue_render(*windowed_program_3d.per_object_transform_renderer, it.render_object_index);

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
            is_key_down (xx #char "V"),
            is_key_down (Input.Key_Code.SHIFT),
        }; 


        velocity.* = get_new_god_mode_velocity(velocity.*, get_forward(*windowed_program_3d.camera), gmi, delta_time);
    } 
    if (movement_mode == .FPS) {
        fpmi := First_Person_Movement_Input.{
            is_key_down (xx #char "W"),
            is_key_down (xx #char "S"),
            is_key_down (xx #char "D"),
            is_key_down (xx #char "A"),
            is_key_down (xx #char "V"),
        }; 

        ground_state : Ground_State = ifx on_ground.* then .ON_GROUND else .IN_AIR;

        velocity.* = get_new_first_person_velocity(velocity.*, fpmi, get_forward(*windowed_program_3d.camera), delta_time, ground_state, Movement_Params.{});
        // log("on_ground: %", on_ground.*);
        // log("delta_time: %", delta_time);
        // log("vel: %", velocity.*);
    }

    windowed_program_3d.camera.position += velocity.* * delta_time;

    // the camera matrices are "one update behind" but it doesn't matter too much here.

    resolve_collisions_against_body(map, character, *windowed_program_3d.camera.position, velocity, on_ground);

    glUseProgram(windowed_program_3d.per_object_transform_renderer.shader_program_gl_handle);

    Simp.update_window (windowed_program_3d.window);
    Simp.clear_render_target(.15, .08, .08, 1);

    glDepthMask (GL_TRUE);
    glEnable (GL_DEPTH_TEST);

    glClear (GL_DEPTH_BUFFER_BIT);

    render(*windowed_program_3d.per_object_transform_renderer);

    Simp.swap_buffers(windowed_program_3d.window);
}


main :: () {

    windowed_program_3d : Windowed_Program_3D;
    windowed_program_3d.movement_mode = .MANUAL;
    windowed_program_3d.camera_mode = .THIRD_PERSON;
    windowed_program_3d.window_width = 1280;
    windowed_program_3d.window_height = 720;
    windowed_program_3d.window_name = "mwe_collision";

    init(*windowed_program_3d);
    // enable_fullscreen(*windowed_program_3d);


    obj_data := load_obj("data/basic_map.obj");
    // just assuming that meshes live till the end of the program for now.
    meshes := convert_obj_to_indexed_meshes(*obj_data);

    map : [..] Collision_Geometry;

    movement_mode := Movement_Mode.FPS;

    // hide_cursor();

    for meshes {
        cg : Collision_Geometry;
        cg.indexed_triangle_positions.indices = it.indices;
        cg.indexed_triangle_positions.positions = it.positions;

        cg.aabb = create_aabb_from_positions(cg.indexed_triangle_positions.positions);

        array_add(*map, cg);
    }

    character : Character;
    character.indexed_triangle_positions = generate_box(ZERO3, 0.4, 1.75, 0.4); 
    character.aabb = create_aabb_from_positions(character.indexed_triangle_positions.positions);
    character.indexed_mesh.indices = character.indexed_triangle_positions.indices;
    character.indexed_mesh.positions = character.indexed_triangle_positions.positions;

    for 1..character.indexed_mesh.positions.count array_add(*character.indexed_mesh.rgb_colors, .{0, .5, .5});
    for 1..character.indexed_mesh.positions.count array_add(*character.local_to_world_indices, xx 0);

    character.render_object_index = buffer_object(*windowed_program_3d.per_object_transform_renderer, character.indexed_mesh.indices, character.local_to_world_indices, character.indexed_mesh.positions, character.indexed_mesh.rgb_colors);


    windowed_program_3d.camera.position = Y3 * 30;
    velocity : Vector3;
    on_ground : bool;

    renderables : [..] Renderable;
    
    count := 10;
    for meshes {
        renderable: Renderable;
        renderable.indexed_mesh = it;
        
        for 1..renderable.indexed_mesh.positions.count array_add(*renderable.local_to_world_indices, xx count);

        renderable.render_object_index = buffer_object(*windowed_program_3d.per_object_transform_renderer, renderable.indexed_mesh.indices, renderable.local_to_world_indices, renderable.indexed_mesh.positions, renderable.indexed_mesh.rgb_colors);

        array_add(*renderables, renderable);

        count += 1;
    }

	delta_time := 0.01667;
    quit := false;
    while !windowed_program_3d.end_program {

        frame_start := current_time_monotonic ();

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

        if is_key_down(xx #char "M")
            toggle_menu(*windowed_program_3d);
    
        for Input.get_window_resizes() {
            Simp.update_window(it.window);  
            if it.window == windowed_program_3d.window {
                should_reinit := (it.width != windowed_program_3d.window_width) || (it.height != windowed_program_3d.window_height);

                windowed_program_3d.window_width  = it.width;
                windowed_program_3d.window_height = it.height;
            }
        }

        per_frame_update(*windowed_program_3d, delta_time);

        if (windowed_program_3d.current_menu == .NONE) {
            do_collision_simulation(*windowed_program_3d, delta_time, *velocity, *on_ground, *character, map, renderables, movement_mode);
        } else {
            context.simp.current_shader = null;
            clear_render_target(.35, .35, .35, 1);
            render_menus(*windowed_program_3d.wp);
            swap_buffers(windowed_program_3d.window);
        }

		frame_end := current_time_monotonic();
		delta_time = cast (float) to_float64_seconds(frame_end - frame_start);

    }

}
